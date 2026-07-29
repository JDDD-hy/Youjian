create function public.next_goal_period(p_timezone text,p_period public.period_type,p_at timestamptz default now()) returns tstzrange
language plpgsql stable security definer set search_path='' as $$
declare local_now timestamp:=p_at at time zone p_timezone; start_local timestamp; end_local timestamp;
begin
 if p_period='daily' then start_local:=date_trunc('day',local_now)+interval '1 day'; end_local:=start_local+interval '1 day';
 elsif p_period='weekly' then start_local:=date_trunc('week',local_now)+interval '1 week'; end_local:=start_local+interval '1 week';
 else start_local:=date_trunc('month',local_now)+interval '1 month'; end_local:=start_local+interval '1 month'; end if;
 return tstzrange(start_local at time zone p_timezone,end_local at time zone p_timezone,'[)');
end $$;

create function public.proposal_json(p_proposal_id uuid,p_member_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('proposal_id',p.id,'proposer',jsonb_build_object('member_id',pm.id,'display_name',pm.display_name),
  'goal_type',p.goal_type,'period_type',p.period_type,'target_value',p.target_value,'status',p.status,'created_at',p.created_at,
  'expires_at',p.expires_at,'effective_period_start',p.effective_period_start,
  'required_vote_count',(select count(*) from public.goal_proposal_members x where x.proposal_id=p.id),
  'accepted_vote_count',(select count(*) from public.goal_proposal_members x where x.proposal_id=p.id and x.vote='accepted'),
  'my_vote',(select vote from public.goal_proposal_members x where x.proposal_id=p.id and x.member_id=p_member_id))
 from public.goal_proposals p join public.space_members pm on pm.id=p.proposer_member_id where p.id=p_proposal_id
$$;

create function public.goal_progress_json(p_goal_id uuid,p_at timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g public.goals%rowtype; tz text; seconds int; members jsonb; done boolean; shared_days int; target_seconds int;
begin
 select * into g from public.goals where id=p_goal_id; select timezone,daily_checkin_target_minutes*60 into tz,target_seconds from public.spaces where id=g.space_id;
 if g.goal_type='group_total_minutes' then
  select coalesce(sum(floor(extract(epoch from(least(fs.ended_at,g.ends_at)-greatest(fs.started_at,g.starts_at))))),0)::int into seconds
  from public.focus_segments fs join public.focus_sessions s on s.id=fs.session_id join public.goal_participants gp on gp.member_id=s.member_id and gp.goal_id=g.id
  where s.status='completed' and fs.ended_at>g.starts_at and fs.started_at<least(g.ends_at,p_at);
  return jsonb_build_object('credited_value',seconds/60,'completed',seconds>=g.target_value*60,'members',null);
 elsif g.goal_type='per_member_minutes' then
  with vals as (select m.id,m.display_name,coalesce(sum(floor(extract(epoch from(least(fs.ended_at,g.ends_at)-greatest(fs.started_at,g.starts_at))))) filter(where s.status='completed'),0)::int sec
   from public.goal_participants gp join public.space_members m on m.id=gp.member_id
   left join public.focus_sessions s on s.member_id=m.id left join public.focus_segments fs on fs.session_id=s.id and fs.ended_at>g.starts_at and fs.started_at<least(g.ends_at,p_at)
   where gp.goal_id=g.id group by m.id,m.display_name)
  select coalesce(jsonb_agg(jsonb_build_object('member_id',id,'display_name',display_name,'credited_value',sec/60,'completed',sec>=g.target_value*60) order by display_name),'[]'),bool_and(sec>=g.target_value*60) into members,done from vals;
  return jsonb_build_object('credited_value',null,'completed',coalesce(done,false),'members',members);
 else
  with local_days as (select d::date as local_date from generate_series((g.starts_at at time zone tz)::date,((least(g.ends_at,p_at)-interval '1 microsecond') at time zone tz)::date,interval '1 day') d),
  qualifying as (select d.local_date from local_days d where not exists(select 1 from public.goal_participants gp join public.space_members m on m.id=gp.member_id
    where gp.goal_id=g.id and public.credited_seconds_for_day(g.space_id,m.user_id,d.local_date,tz)<target_seconds))
  select count(*)::int into shared_days from qualifying;
  return jsonb_build_object('credited_value',shared_days,'completed',shared_days>=g.target_value,'members',null);
 end if;
end $$;

create function public.goal_json(p_goal_id uuid,p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('goal_id',g.id,'goal_type',g.goal_type,'period_type',g.period_type,'target_value',g.target_value,
  'status',g.status,'starts_at',g.starts_at,'ends_at',g.ends_at,'progress',public.goal_progress_json(g.id,p_at)) from public.goals g where g.id=p_goal_id
$$;

create function public.propose_goal(p_space_id uuid,p_goal_type text,p_period_type text,p_target_value integer,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; gt public.goal_type; pt public.period_type; bounds tstzrange; pid uuid; h text; cached jsonb; result jsonb; member_count int;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 h:=encode(extensions.digest(convert_to(p_space_id::text||'|'||coalesce(p_goal_type,'')||'|'||coalesce(p_period_type,'')||'|'||coalesce(p_target_value::text,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'propose_goal',h); if cached is not null then return cached; end if;
 select * into m from public.space_members where space_id=p_space_id and user_id=a; if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 begin gt:=p_goal_type::public.goal_type; exception when invalid_text_representation then return public.api_error('INVALID_GOAL_TYPE'); end;
 begin pt:=p_period_type::public.period_type; exception when invalid_text_representation then return public.api_error('INVALID_PERIOD_TYPE'); end;
 if p_target_value is null or p_target_value<1 or (gt='shared_checkin_days' and ((pt='daily' and p_target_value>1) or (pt='weekly' and p_target_value>7) or (pt='monthly' and p_target_value>31))) then return public.api_error('INVALID_TARGET_VALUE'); end if;
 select count(*) into member_count from public.space_members where space_id=p_space_id and status='active'; if member_count<2 then return public.api_error('NOT_ENOUGH_MEMBERS'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_space_id::text,0));
 bounds:=public.next_goal_period((select timezone from public.spaces where id=p_space_id),pt); pid:=gen_random_uuid();
 insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start)
 values(pid,p_space_id,m.id,gt,pt,p_target_value,'pending',now()+interval '48 hours',lower(bounds));
 insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at)
 select pid,id,case when id=m.id then 'accepted'::public.goal_vote end,case when id=m.id then now() end from public.space_members where space_id=p_space_id and status='active';
 result:=public.api_ok(jsonb_build_object('proposal',public.proposal_json(pid,m.id),'goal',null));
 return public.store_command(a,p_idempotency_key,'propose_goal',h,null,result);
end $$;

create function public.vote_goal_proposal(p_proposal_id uuid,p_vote text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); p public.goal_proposals%rowtype; m public.space_members%rowtype; v public.goal_vote; h text; cached jsonb; gid uuid; bounds tstzrange; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 h:=p_proposal_id::text||'|'||coalesce(p_vote,''); cached:=public.command_cached(a,p_idempotency_key,'vote_goal_proposal',h); if cached is not null then return cached; end if;
 begin v:=p_vote::public.goal_vote; exception when invalid_text_representation then return public.api_error('INVALID_VOTE'); end;
 select * into p from public.goal_proposals where id=p_proposal_id for update; if not found then return public.api_error('PROPOSAL_NOT_FOUND'); end if;
 select * into m from public.space_members where space_id=p.space_id and user_id=a; if not found or m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 if p.status='pending' and now()>=p.expires_at then update public.goal_proposals set status='expired',resolved_at=now() where id=p.id; p.status:='expired'; end if;
 if p.status<>'pending' then return public.api_error('PROPOSAL_NOT_PENDING','{}',public.proposal_json(p.id,m.id)); end if;
 if not exists(select 1 from public.goal_proposal_members where proposal_id=p.id and member_id=m.id) then return public.api_error('NOT_ELIGIBLE_TO_VOTE'); end if;
 if exists(select 1 from public.goal_proposal_members where proposal_id=p.id and member_id=m.id and vote is not null) then return public.api_error('VOTE_ALREADY_FINAL','{}',public.proposal_json(p.id,m.id)); end if;
 update public.goal_proposal_members set vote=v,voted_at=now() where proposal_id=p.id and member_id=m.id;
 if v='rejected' then update public.goal_proposals set status='rejected',resolved_at=now() where id=p.id;
 elsif not exists(select 1 from public.goal_proposal_members where proposal_id=p.id and vote is distinct from 'accepted') then
  update public.goal_proposals set status='accepted',resolved_at=now() where id=p.id;
  bounds:=public.next_goal_period((select timezone from public.spaces where id=p.space_id),p.period_type,p.created_at); gid:=gen_random_uuid();
  insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status)
   values(gid,p.id,p.space_id,p.goal_type,p.period_type,p.target_value,lower(bounds),upper(bounds),'scheduled');
  insert into public.goal_participants(goal_id,member_id) select gid,member_id from public.goal_proposal_members where proposal_id=p.id;
 end if;
 result:=public.api_ok(jsonb_build_object('proposal',public.proposal_json(p.id,m.id),'goal',case when gid is null then null else public.goal_json(gid) end));
 return public.store_command(a,p_idempotency_key,'vote_goal_proposal',h,null,result);
end $$;

create function public.run_goal_maintenance(p_at timestamptz default now()) returns jsonb
language sql security definer set search_path='' as $$ select '{}'::jsonb $$;

create function public.get_goals_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m uuid; active jsonb; scheduled jsonb; pending jsonb; history jsonb;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select id into m from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active'; perform public.run_goal_maintenance(now());
 select coalesce(jsonb_agg(public.goal_json(id) order by starts_at),'[]') into active from public.goals where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(public.goal_json(id) order by starts_at),'[]') into scheduled from public.goals where space_id=p_space_id and status='scheduled';
 select coalesce(jsonb_agg(public.proposal_json(id,m) order by created_at desc),'[]') into pending from public.goal_proposals where space_id=p_space_id and status='pending';
 select coalesce(jsonb_agg(public.goal_json(id) order by ends_at desc),'[]') into history from public.goals where space_id=p_space_id and status in ('completed','failed');
 return public.api_ok(jsonb_build_object('active_goals',active,'scheduled_goals',scheduled,'pending_proposals',pending,'history',history));
end $$;

create or replace function public.run_goal_maintenance(p_at timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; progress jsonb; expired int:=0; activated int:=0; resolved int:=0; awards int:=0; tz text; d date; target int; all_done boolean; threshold int;
begin
 update public.goal_proposals set status='expired',resolved_at=p_at where status='pending' and expires_at<=p_at; get diagnostics expired=row_count;
 update public.goals set status='active' where status='scheduled' and starts_at<=p_at and ends_at>p_at; get diagnostics activated=row_count;
 for r in select * from public.goals where status='active' for update skip locked loop
  progress:=public.goal_progress_json(r.id,p_at);
  if (progress->>'completed')::boolean then update public.goals set status='completed',completed_at=p_at where id=r.id; resolved:=resolved+1;
  elsif r.ends_at<=p_at then update public.goals set status='failed',completed_at=r.ends_at where id=r.id; resolved:=resolved+1; end if;
 end loop;
 insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
 select g.space_id,'first_goal','first-goal:'||g.id,g.completed_at,jsonb_build_object('goal_id',g.id)
 from public.goals g where g.status='completed' and not exists(select 1 from public.achievements a where a.space_id=g.space_id and a.achievement_type='first_goal')
 on conflict(space_id,dedupe_key) do nothing; get diagnostics awards=row_count;
 for r in select s.id,s.timezone,s.daily_checkin_target_minutes from public.spaces s loop
  tz:=r.timezone; target:=r.daily_checkin_target_minutes*60;
  for d in select (p_at at time zone tz)::date union select (p_at at time zone tz)::date-1 loop
   select count(*)>1 and bool_and(public.credited_seconds_for_day(r.id,m.user_id,d,tz)>=target) into all_done from public.space_members m where m.space_id=r.id and m.status='active';
   if all_done then insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'together_lit','together-lit:'||d,p_at,jsonb_build_object('local_date',d)) on conflict do nothing; end if;
  end loop;
  if exists(select 1 from generate_series(0,2) n where not exists(select 1 from public.achievements a where a.space_id=r.id and a.dedupe_key='together-lit:'||((p_at at time zone tz)::date-n)::text)) then null;
  else insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'three_days_together','three-days:'||((p_at at time zone tz)::date),p_at,jsonb_build_object('period_end_date',(p_at at time zone tz)::date)) on conflict do nothing; end if;
  foreach threshold in array array[600,3000,6000] loop
   if (select coalesce(sum(accumulated_focus_seconds),0) from public.focus_sessions where space_id=r.id and status='completed')>=threshold*60 then
    insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'focus_milestone','milestone:'||threshold,p_at,jsonb_build_object('threshold_minutes',threshold)) on conflict do nothing;
   end if;
  end loop;
 end loop;
 return jsonb_build_object('expired_proposals',expired,'activated_goals',activated,'resolved_goals',resolved,'awards',awards);
end $$;

create function public.list_achievements(p_space_id uuid,p_limit integer default 30,p_cursor text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cursor_time timestamptz; cursor_id uuid; items jsonb; next_cursor text; v_member_id uuid;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
 if p_cursor is not null then begin cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz; cursor_id:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2)::uuid; exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
 select id into v_member_id from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active';
 with rows as (select a.*,row_number() over(order by earned_at desc,id desc) rn from public.achievements a where space_id=p_space_id and (p_cursor is null or (earned_at,id)<(cursor_time,cursor_id)) order by earned_at desc,id desc limit p_limit+1),
 chosen as(select * from rows where rn<=p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('achievement_id',id,'achievement_type',achievement_type,'earned_at',earned_at,'metadata',metadata,
  'seen',exists(select 1 from public.achievement_reads ar where ar.achievement_id=id and ar.member_id=v_member_id)) order by earned_at desc,id desc),'[]'),
 case when (select count(*) from rows)>p_limit then (select encode(convert_to(earned_at::text||'|'||id::text,'UTF8'),'base64') from chosen order by earned_at,id limit 1) end into items,next_cursor from chosen;
 return public.api_ok(jsonb_build_object('items',items,'next_cursor',next_cursor));
end $$;

create function public.mark_achievement_seen(p_achievement_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); ac public.achievements%rowtype; m uuid; h text:=p_achievement_id::text; cached jsonb; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'mark_achievement_seen',h); if cached is not null then return cached; end if;
 select * into ac from public.achievements where id=p_achievement_id; if not found or not public.current_user_is_active_member(ac.space_id) then return public.api_error('ACHIEVEMENT_NOT_FOUND'); end if;
 select id into m from public.space_members where space_id=ac.space_id and user_id=a and status='active';
 insert into public.achievement_reads(achievement_id,member_id) values(ac.id,m) on conflict do nothing;
 result:=public.api_ok(jsonb_build_object('achievement_id',ac.id,'seen',true)); return public.store_command(a,p_idempotency_key,'mark_achievement_seen',h,null,result);
end $$;

create function public.get_space_settings(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.spaces%rowtype; m public.space_members%rowtype; tz text; members jsonb; owner boolean;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into s from public.spaces where id=p_space_id; select * into m from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active'; select timezone into tz from public.profiles where id=auth.uid(); owner:=m.role='owner';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',id,'display_name',display_name,'role',role,'status',status,'joined_at',joined_at) order by joined_at),'[]') into members from public.space_members where space_id=p_space_id;
 return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',s.id,'name',s.name,'timezone',s.timezone,'member_limit',s.member_limit,'daily_checkin_target_minutes',s.daily_checkin_target_minutes,'created_at',s.created_at),
  'me',jsonb_build_object('member_id',m.id,'display_name',m.display_name,'role',m.role,'profile_timezone',tz),'members',members,
  'owner_actions',jsonb_build_object('can_copy_invite',owner,'can_rotate_invite',owner,'can_disable_members',owner)));
end $$;

revoke all on function public.next_goal_period(text,public.period_type,timestamptz), public.proposal_json(uuid,uuid), public.goal_progress_json(uuid,timestamptz), public.goal_json(uuid,timestamptz), public.run_goal_maintenance(timestamptz) from public;
grant execute on function public.get_goals_snapshot(uuid), public.propose_goal(uuid,text,text,integer,uuid), public.vote_goal_proposal(uuid,text,uuid),
 public.list_achievements(uuid,integer,text), public.mark_achievement_seen(uuid,uuid), public.get_space_settings(uuid) to authenticated;

alter publication supabase_realtime add table public.goal_proposals;
alter publication supabase_realtime add table public.goals;
alter publication supabase_realtime add table public.achievements;
