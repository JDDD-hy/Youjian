create or replace function public.propose_goal(p_space_id uuid,p_goal_type text,p_period_type text,p_target_value integer,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; gt public.goal_type; pt public.period_type; bounds tstzrange; pid uuid; h text; cached jsonb; result jsonb; member_count int;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_space_id::text,'')||'|'||coalesce(p_goal_type,'')||'|'||coalesce(p_period_type,'')||'|'||coalesce(p_target_value::text,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'propose_goal',h); if cached is not null then return cached; end if;
 begin gt:=p_goal_type::public.goal_type; exception when invalid_text_representation then return public.api_error('INVALID_GOAL_TYPE'); end;
 begin pt:=p_period_type::public.period_type; exception when invalid_text_representation then return public.api_error('INVALID_PERIOD_TYPE'); end;
 if gt is null then return public.api_error('INVALID_GOAL_TYPE'); end if; if pt is null then return public.api_error('INVALID_PERIOD_TYPE'); end if;
 if p_target_value is null or p_target_value<1 or p_target_value>1000000 or (gt='shared_checkin_days' and ((pt='daily' and p_target_value>1) or(pt='weekly' and p_target_value>7)or(pt='monthly' and p_target_value>31))) then return public.api_error('INVALID_TARGET_VALUE'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
 select * into m from public.space_members where space_id=p_space_id and user_id=a;
 if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if; if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 select count(*) into member_count from public.space_members where space_id=p_space_id and status='active'; if member_count<2 then return public.api_error('NOT_ENOUGH_MEMBERS'); end if;
 bounds:=public.next_goal_period((select timezone from public.spaces where id=p_space_id),pt); pid:=gen_random_uuid();
 insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start)
 values(pid,p_space_id,m.id,gt,pt,p_target_value,'pending',now()+interval '48 hours',lower(bounds));
 insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at)
 select pid,id,case when id=m.id then 'accepted'::public.goal_vote end,case when id=m.id then now() end from public.space_members where space_id=p_space_id and status='active';
 result:=public.api_ok(jsonb_build_object('proposal',public.proposal_json(pid,m.id),'goal',null)); return public.store_command(a,p_idempotency_key,'propose_goal',h,null,result);
exception when numeric_value_out_of_range or check_violation or not_null_violation then return public.api_error('INVALID_TARGET_VALUE');
end $$;

create or replace function public.vote_goal_proposal(p_proposal_id uuid,p_vote text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); p public.goal_proposals%rowtype; m public.space_members%rowtype; v public.goal_vote; h text; cached jsonb; gid uuid; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if; if p_vote is null then return public.api_error('INVALID_VOTE'); end if;
 h:=coalesce(p_proposal_id::text,'')||'|'||p_vote; cached:=public.command_cached(a,p_idempotency_key,'vote_goal_proposal',h); if cached is not null then return cached; end if;
 begin v:=p_vote::public.goal_vote; exception when invalid_text_representation then return public.api_error('INVALID_VOTE'); end;
 select * into p from public.goal_proposals where id=p_proposal_id for update;
 if not found or not public.current_user_is_active_member(p.space_id) then return public.api_error('PROPOSAL_NOT_FOUND'); end if;
 select * into m from public.space_members where space_id=p.space_id and user_id=a and status='active';
 if p.status='pending' and now()>=p.expires_at then update public.goal_proposals set status='expired',resolved_at=now() where id=p.id; p.status:='expired'; end if;
 if p.status<>'pending' then return public.api_error('PROPOSAL_NOT_PENDING','{}',public.proposal_json(p.id,m.id)); end if;
 if not exists(select 1 from public.goal_proposal_members where proposal_id=p.id and member_id=m.id) then return public.api_error('NOT_ELIGIBLE_TO_VOTE'); end if;
 if exists(select 1 from public.goal_proposal_members where proposal_id=p.id and member_id=m.id and vote is not null) then return public.api_error('VOTE_ALREADY_FINAL','{}',public.proposal_json(p.id,m.id)); end if;
 update public.goal_proposal_members set vote=v,voted_at=now() where proposal_id=p.id and member_id=m.id;
 if v='rejected' then update public.goal_proposals set status='rejected',resolved_at=now() where id=p.id;
 else gid:=public.accept_proposal_if_ready(p.id,now()); end if;
 result:=public.api_ok(jsonb_build_object('proposal',public.proposal_json(p.id,m.id),'goal',case when gid is null then null else public.goal_json(gid) end));
 return public.store_command(a,p_idempotency_key,'vote_goal_proposal',h,null,result);
end $$;

create or replace function public.disable_member(p_space_id uuid,p_member_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_space_id::text,'')||'|'||coalesce(p_member_id::text,''); cached jsonb; m public.space_members%rowtype; sid uuid; result jsonb; r record; gid uuid; resolved jsonb:='[]'::jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'disable_member',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
 if not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
 select * into m from public.space_members where id=p_member_id and space_id=p_space_id for update;
 if not found then return public.api_error('MEMBER_NOT_FOUND'); end if; if m.role='owner' then return public.api_error('CANNOT_DISABLE_OWNER'); end if; if m.status='disabled' then return public.api_error('MEMBER_ALREADY_DISABLED'); end if;
 select id into sid from public.focus_sessions where member_id=m.id and status in('focusing','paused') for update; if sid is not null then perform public.finish_focus_session(sid,now(),'member_disabled'); end if;
 update public.space_members set status='disabled',disabled_at=now(),disabled_by=a where id=m.id;
 for r in select gp.id from public.goal_proposals gp join public.goal_proposal_members gpm on gpm.proposal_id=gp.id where gp.space_id=p_space_id and gp.status='pending' and gpm.member_id=m.id for update of gp loop
  delete from public.goal_proposal_members where proposal_id=r.id and member_id=m.id; gid:=public.accept_proposal_if_ready(r.id,now()); if gid is not null then resolved:=resolved||jsonb_build_array(jsonb_build_object('proposal_id',r.id,'goal_id',gid)); end if;
 end loop;
 result:=public.api_ok(jsonb_build_object('member',jsonb_build_object('member_id',m.id,'status','disabled','disabled_at',now()),'settled_session',case when sid is null then null else public.session_json(sid) end,'resolved_proposals',resolved));
 return public.store_command(a,p_idempotency_key,'disable_member',h,sid,result);
end $$;

create or replace function public.run_goal_maintenance(p_at timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; progress jsonb; expired int:=0; activated int:=0; missed int:=0; resolved int:=0; awards int:=0; tz text; d date; target int; all_done boolean; threshold int;
begin
 update public.goal_proposals set status='expired',resolved_at=p_at where status='pending' and expires_at<=p_at; get diagnostics expired=row_count;
 update public.goals set status='failed',completed_at=ends_at where status='scheduled' and ends_at<=p_at; get diagnostics missed=row_count;
 update public.goals set status='active' where status='scheduled' and starts_at<=p_at and ends_at>p_at; get diagnostics activated=row_count;
 for r in select * from public.goals where status='active' for update skip locked loop
  progress:=public.goal_progress_json(r.id,p_at);
  if(progress->>'completed')::boolean then update public.goals set status='completed',completed_at=p_at where id=r.id; resolved:=resolved+1;
  elsif r.ends_at<=p_at then update public.goals set status='failed',completed_at=r.ends_at where id=r.id; resolved:=resolved+1; end if;
 end loop;
 with firsts as(select distinct on(g.space_id) g.space_id,g.id,g.completed_at from public.goals g where g.status='completed' order by g.space_id,g.completed_at,g.id)
 insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
 select f.space_id,'first_goal','first-goal',f.completed_at,jsonb_build_object('goal_id',f.id) from firsts f
 where not exists(select 1 from public.achievements a where a.space_id=f.space_id and a.achievement_type='first_goal') on conflict(space_id,dedupe_key) do nothing;
 get diagnostics awards=row_count;
 for r in select s.id,s.timezone,s.daily_checkin_target_minutes from public.spaces s loop
  tz:=r.timezone; target:=r.daily_checkin_target_minutes*60;
  for d in select(p_at at time zone tz)::date union select(p_at at time zone tz)::date-1 loop
   select count(*)>1 and bool_and(public.credited_seconds_for_day(r.id,m.user_id,d,tz)>=target) into all_done from public.space_members m where m.space_id=r.id and m.status='active';
   if all_done then insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'together_lit','together-lit:'||d,p_at,jsonb_build_object('local_date',d)) on conflict do nothing; end if;
  end loop;
  if not exists(select 1 from generate_series(0,2)n where not exists(select 1 from public.achievements a where a.space_id=r.id and a.dedupe_key='together-lit:'||((p_at at time zone tz)::date-n)::text)) then
   insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'three_days_together','three-days:'||((p_at at time zone tz)::date),p_at,jsonb_build_object('period_end_date',(p_at at time zone tz)::date)) on conflict do nothing;
  end if;
  foreach threshold in array array[600,3000,6000] loop
   if(select coalesce(sum(accumulated_focus_seconds),0) from public.focus_sessions where space_id=r.id and status='completed')>=threshold::bigint*60 then
    insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'focus_milestone','milestone:'||threshold,p_at,jsonb_build_object('threshold_minutes',threshold)) on conflict do nothing;
   end if;
  end loop;
 end loop;
 return jsonb_build_object('expired_proposals',expired,'activated_goals',activated,'missed_goals',missed,'resolved_goals',resolved,'awards',awards);
end $$;

create function public.run_minute_maintenance_core(p_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; settled int:=0; uncertain int:=0; goals jsonb;
begin
 for r in select id from public.focus_sessions where(status='paused' and paused_at+interval '15 minutes'<=p_at)or(status='focusing' and active_segment_started_at+make_interval(secs=>21600-accumulated_focus_seconds)<=p_at) order by started_at limit 100 for update skip locked
 loop perform public.settle_session(r.id,p_at); settled:=settled+1; end loop;
 for r in select id,last_seen_at from public.focus_sessions where status='focusing' and last_seen_at+interval '120 seconds'<=p_at order by last_seen_at limit 100 for update skip locked loop
  if not exists(select 1 from public.focus_connection_intervals where session_id=r.id and ended_at is null) then
   insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(r.id,r.last_seen_at+interval '120 seconds',r.last_seen_at);
   perform public.record_focus_event(r.id,null,'connection_unconfirmed',r.last_seen_at+interval '120 seconds'); update public.focus_sessions set version=version+1 where id=r.id; uncertain:=uncertain+1;
  end if;
 end loop;
 goals:=public.run_goal_maintenance(p_at); delete from public.focus_commands where created_at<p_at-interval '30 days';
 return jsonb_build_object('settled_sessions',settled,'new_unconfirmed_intervals',uncertain,'goal_maintenance',goals,'ran_at',p_at);
end $$;

create or replace function public.run_minute_maintenance() returns jsonb
language plpgsql security definer set search_path='' as $$
declare run_id bigint; output jsonb; t timestamptz:=now();
begin
 insert into private.maintenance_runs(job_name,started_at,status) values('minute_maintenance',t,'running') returning id into run_id;
 begin
  output:=public.run_minute_maintenance_core(t); update private.maintenance_runs set finished_at=clock_timestamp(),status='succeeded',result=output where id=run_id; return output;
 exception when others then
  update private.maintenance_runs set finished_at=clock_timestamp(),status='failed',error_code=sqlstate,result=jsonb_build_object('message','maintenance failed') where id=run_id;
  return jsonb_build_object('ok',false,'error_code','MAINTENANCE_FAILED','run_id',run_id,'ran_at',t);
 end;
end $$;

create or replace function public.get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); sp public.spaces%rowtype; me public.space_members%rowtype; my_sid uuid; friends jsonb; today_seconds int; streak int; today_date date; profile_tz text; active_count int; active_goal jsonb;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into sp from public.spaces where id=p_space_id; select * into me from public.space_members where space_id=p_space_id and user_id=a and status='active'; select timezone into profile_tz from public.profiles where id=a;
 perform public.settle_session(id,now()) from public.focus_sessions where space_id=p_space_id and status in('focusing','paused'); perform public.run_minute_maintenance();
 select id into my_sid from public.focus_sessions where user_id=a and status in('focusing','paused'); select count(*) into active_count from public.space_members where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name,'session_id',s.id,'task_name',s.task_name,'category',s.category,'status',s.status,'accumulated_focus_seconds',s.accumulated_focus_seconds,'active_segment_started_at',s.active_segment_started_at,'connection',jsonb_build_object('status',case when now()-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,'last_seen_at',s.last_seen_at))order by m.joined_at),'[]') into friends
 from public.focus_sessions s join public.space_members m on m.id=s.member_id where s.space_id=p_space_id and s.user_id<>a and s.status='focusing' and m.status='active';
 today_date:=(now() at time zone profile_tz)::date; today_seconds:=public.credited_seconds_for_day(p_space_id,a,today_date,profile_tz); streak:=public.current_streak_days(p_space_id,a,profile_tz);
 select public.goal_json(id) into active_goal from public.goals where space_id=p_space_id and status='active' order by ends_at,id limit 1;
 return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sp.id,'name',sp.name,'timezone',sp.timezone,'active_member_count',active_count,'member_limit',sp.member_limit,'daily_checkin_target_minutes',sp.daily_checkin_target_minutes),
 'me',jsonb_build_object('member_id',me.id,'display_name',me.display_name,'role',me.role,'profile_timezone',profile_tz),'my_session',case when my_sid is null then null else public.session_json(my_sid) end,'focusing_members',friends,
 'today',jsonb_build_object('credited_focus_seconds',today_seconds,'checkin_target_seconds',sp.daily_checkin_target_minutes*60,'checkin_completed',today_seconds>=sp.daily_checkin_target_minutes*60,'current_streak_days',streak),
 'active_goal_summary',active_goal,'unseen_achievement',(select jsonb_build_object('achievement_id',ac.id,'achievement_type',ac.achievement_type,'earned_at',ac.earned_at,'metadata',ac.metadata) from public.achievements ac left join public.achievement_reads ar on ar.achievement_id=ac.id and ar.member_id=me.id where ac.space_id=p_space_id and ar.achievement_id is null order by ac.earned_at limit 1)));
end $$;

revoke all on function public.run_minute_maintenance_core(timestamptz) from public;
