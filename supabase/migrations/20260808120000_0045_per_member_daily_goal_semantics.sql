-- A per-member threshold is a daily promise repeated for every local day in
-- the selected period, not one cumulative threshold for the whole period.

create or replace function public.goal_progress_json(p_goal_id uuid,p_at timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g public.goals%rowtype; tz text; seconds int; members jsonb; done boolean; shared_days int; target_seconds int; progress_at timestamptz; required_days int; current_day date;
begin
 select * into g from public.goals where id=p_goal_id;
 select timezone,daily_checkin_target_minutes*60 into tz,target_seconds from public.spaces where id=g.space_id;
 progress_at:=least(g.ends_at,p_at,case when g.status in('completed','failed') then g.completed_at else p_at end);
 if g.goal_type='group_total_minutes' then
  select coalesce(floor(sum(extract(epoch from(least(fs.ended_at,progress_at)-greatest(fs.started_at,g.starts_at))))),0)::int into seconds
  from public.focus_segments fs join public.focus_sessions s on s.id=fs.session_id join public.goal_participants gp on gp.member_id=s.member_id and gp.goal_id=g.id
  where s.status='completed' and fs.ended_at>g.starts_at and fs.started_at<progress_at;
  return jsonb_build_object('credited_value',seconds/60,'completed',seconds>=g.target_value*60,'members',null);
 elsif g.goal_type='per_member_minutes' then
  required_days:=((g.ends_at at time zone tz)::date-(g.starts_at at time zone tz)::date);
  current_day:=(least(progress_at,g.ends_at-interval '1 microsecond') at time zone tz)::date;
  with local_days as(
    select d::date local_date from generate_series(
      (g.starts_at at time zone tz)::date,
      ((g.ends_at-interval '1 microsecond') at time zone tz)::date,
      interval '1 day'
    ) d
  ), member_days as(
    select m.id,m.display_name,d.local_date,
      coalesce((select floor(sum(extract(epoch from(
        least(seg.ended_at,(d.local_date+1)::timestamp at time zone tz,progress_at)-
        greatest(seg.started_at,d.local_date::timestamp at time zone tz)
      ))))::int
      from public.focus_sessions s join public.focus_segments seg on seg.session_id=s.id
      where s.space_id=g.space_id and s.user_id=m.user_id and s.status='completed' and seg.ended_at is not null
        and seg.started_at<least((d.local_date+1)::timestamp at time zone tz,progress_at)
        and seg.ended_at>d.local_date::timestamp at time zone tz),0) sec
    from public.goal_participants gp join public.space_members m on m.id=gp.member_id cross join local_days d
    where gp.goal_id=g.id
  ), vals as(
    select id,display_name,
      count(*) filter(where sec>=g.target_value*60)::int completed_days,
      coalesce(max(sec) filter(where local_date=current_day),0)::int current_day_seconds
    from member_days group by id,display_name
  ) select coalesce(jsonb_agg(jsonb_build_object(
      'member_id',id,'display_name',display_name,
      'credited_value',completed_days,'completed_days',completed_days,'required_days',required_days,
      'current_day_credited_minutes',current_day_seconds/60,
      'completed',completed_days>=required_days
    ) order by display_name),'[]'::jsonb),bool_and(completed_days>=required_days)
    into members,done from vals;
  return jsonb_build_object('credited_value',null,'completed',coalesce(done,false),'members',members,
    'required_days',required_days,'target_minutes_per_day',g.target_value);
 else
  with local_days as(select d::date local_date from generate_series((g.starts_at at time zone tz)::date,((progress_at-interval '1 microsecond') at time zone tz)::date,interval '1 day') d),
  qualifying as(select d.local_date from local_days d where not exists(select 1 from public.goal_participants gp join public.space_members m on m.id=gp.member_id where gp.goal_id=g.id and public.credited_seconds_for_day(g.space_id,m.user_id,d.local_date,tz)<target_seconds))
  select count(*)::int into shared_days from qualifying;
  return jsonb_build_object('credited_value',shared_days,'completed',shared_days>=g.target_value,'members',null);
 end if;
end $$;

revoke all on function public.goal_progress_json(uuid,timestamptz) from public;

create or replace function private.rpc_impl_propose_goal(p_space_id uuid,p_goal_type text,p_period_type text,p_target_value integer,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; gt public.goal_type; pt public.period_type; bounds tstzrange; pid uuid; h text; cached jsonb; result jsonb; member_count int;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_space_id::text,'')||'|'||coalesce(p_goal_type,'')||'|'||coalesce(p_period_type,'')||'|'||coalesce(p_target_value::text,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'propose_goal',h); if cached is not null then return cached; end if;
 begin gt:=p_goal_type::public.goal_type; exception when invalid_text_representation then return public.api_error('INVALID_GOAL_TYPE'); end;
 begin pt:=p_period_type::public.period_type; exception when invalid_text_representation then return public.api_error('INVALID_PERIOD_TYPE'); end;
 if gt is null then return public.api_error('INVALID_GOAL_TYPE'); end if;
 if pt is null then return public.api_error('INVALID_PERIOD_TYPE'); end if;
 if p_target_value is null or p_target_value<1
   or (gt='group_total_minutes' and p_target_value>1000000)
   or (gt='per_member_minutes' and p_target_value>720)
   or (gt='shared_checkin_days' and ((pt='daily' and p_target_value>1) or (pt='weekly' and p_target_value>7) or (pt='monthly' and p_target_value>31)))
 then return public.api_error('INVALID_TARGET_VALUE'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
 select * into m from public.space_members where space_id=p_space_id and user_id=a;
 if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if; if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 if exists(select 1 from public.goal_proposals where space_id=p_space_id and status='pending') or exists(select 1 from public.goals where space_id=p_space_id and status in('scheduled','active')) then return public.api_error('GOAL_ALREADY_OPEN'); end if;
 select count(*) into member_count from public.space_members where space_id=p_space_id and status='active'; if member_count<2 then return public.api_error('NOT_ENOUGH_MEMBERS'); end if;
 bounds:=public.next_goal_period((select timezone from public.spaces where id=p_space_id),pt,now()); pid:=gen_random_uuid();
 insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start)
 values(pid,p_space_id,m.id,gt,pt,p_target_value,'pending',now()+interval '48 hours',lower(bounds));
 insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at)
 select pid,id,case when id=m.id then 'accepted'::public.goal_vote end,case when id=m.id then now() end from public.space_members where space_id=p_space_id and status='active';
 result:=public.api_ok(jsonb_build_object('proposal',public.proposal_json(pid,m.id),'goal',null));
 return public.store_command(a,p_idempotency_key,'propose_goal',h,null,result);
exception when numeric_value_out_of_range or check_violation or not_null_violation then return public.api_error('INVALID_TARGET_VALUE');
end $$;

revoke all on function private.rpc_impl_propose_goal(uuid,text,text,integer,uuid) from public,anon,authenticated;
