-- Snapshot the browser's current IANA timezone for every focus. This keeps
-- personal achievements local to where the focus actually happened while
-- retaining the space timezone as the shared natural-day boundary.

create function private.rpc_impl_start_focus(
  p_space_id uuid,p_task_name text,p_category text,p_timezone text,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; h text; cached jsonb; active_id uuid; sid uuid; result jsonb; cat public.focus_category;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 if p_category is null then return public.api_error('INVALID_CATEGORY'); end if;
 if not coalesce(public.validate_iana_timezone(p_timezone),false) then return public.api_error('INVALID_TIMEZONE'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_space_id::text,'')||'|'||coalesce(p_task_name,'')||'|'||p_category||'|'||p_timezone,'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'start_focus',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a::text,0));
 select * into m from public.space_members where user_id=a and space_id=p_space_id;
 if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if; if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 if p_task_name is null or char_length(btrim(p_task_name)) not between 1 and 80 then return public.api_error('INVALID_TASK_NAME'); end if;
 begin cat:=p_category::public.focus_category; exception when invalid_text_representation then return public.api_error('INVALID_CATEGORY'); end;
 select id into active_id from public.focus_sessions where user_id=a and status in('focusing','paused') for update;
 if found then perform public.settle_session(active_id,now()); select id into active_id from public.focus_sessions where id=active_id and status in('focusing','paused'); end if;
 if active_id is not null then return public.api_error('SESSION_ALREADY_ACTIVE','{}',public.session_json(active_id)); end if;
 update public.profiles set timezone=p_timezone,updated_at=now() where id=a;
 sid:=gen_random_uuid(); insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
 values(sid,p_space_id,a,m.id,btrim(p_task_name),cat,'focusing',now(),now(),now());
 insert into public.focus_segments(session_id,started_at) values(sid,now()); perform public.record_focus_event(sid,a,'started',now(),jsonb_build_object('timezone',p_timezone));
 result:=public.api_ok(jsonb_build_object('session',public.session_json(sid))); return public.store_command(a,p_idempotency_key,'start_focus',h,sid,result);
exception when check_violation or not_null_violation or invalid_text_representation then return public.api_error('INVALID_REQUEST');
end $$;

create function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_timezone text,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin return private.rpc_impl_start_focus(p_space_id,p_task_name,p_category,p_timezone,p_idempotency_key);
exception when others then return private.rpc_internal_error_envelope('start_focus',sqlstate); end $$;

create or replace function public.session_json(p_session_id uuid,p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
   'session_id',s.id,'space_id',s.space_id,'member_id',s.member_id,'task_name',s.task_name,
   'category',s.category,'task_history',private.focus_task_history_json(s.id),
   'status',s.status,'started_at',s.started_at,'timezone_snapshot',s.timezone_snapshot,
   'accumulated_focus_seconds',s.accumulated_focus_seconds,
   'active_segment_started_at',s.active_segment_started_at,'paused_at',s.paused_at,
   'auto_settle_at',case when s.status='focusing' then s.active_segment_started_at+make_interval(secs=>21600-s.accumulated_focus_seconds)
                         when s.status='paused' then s.paused_at+interval '15 minutes' end,
   'completed_at',s.completed_at,'completion_reason',s.completion_reason,
   'credited_focus_seconds',case when s.status in('completed','discarded') then s.accumulated_focus_seconds end,
   'counts_toward_stats',case when s.status='completed' then true when s.status='discarded' then false end,
   'connection',jsonb_build_object('status',case when s.status='focusing' and p_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,
      'last_seen_at',s.last_seen_at,'unconfirmed_connection_seconds',s.unconfirmed_connection_seconds)
 ) from public.focus_sessions s where s.id=p_session_id
$$;

create or replace function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); sp public.spaces%rowtype; me public.space_members%rowtype; my_sid uuid; friends jsonb; today_seconds int; streak int; today_date date; profile_tz text; active_count int; active_goal jsonb; snapshot_at timestamptz:=now(); target_minutes int; tomorrow_target int; today_locked boolean; today_source text;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into sp from public.spaces where id=p_space_id; select * into me from public.space_members where space_id=p_space_id and user_id=a and status='active'; select timezone into profile_tz from public.profiles where id=a;
 perform private.run_space_maintenance(p_space_id,snapshot_at);
 select id into my_sid from public.focus_sessions where user_id=a and status in('focusing','paused'); select count(*) into active_count from public.space_members where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name,'session_id',s.id,'task_name',s.task_name,'category',s.category,'task_history',private.focus_task_history_json(s.id),'status',s.status,'timezone_snapshot',s.timezone_snapshot,'accumulated_focus_seconds',s.accumulated_focus_seconds,'active_segment_started_at',s.active_segment_started_at,'connection',jsonb_build_object('status',case when snapshot_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,'last_seen_at',s.last_seen_at))order by m.joined_at),'[]') into friends
 from public.focus_sessions s join public.space_members m on m.id=s.member_id where s.space_id=p_space_id and s.user_id<>a and s.status='focusing' and m.status='active';
 today_date:=(snapshot_at at time zone profile_tz)::date; today_seconds:=public.credited_seconds_for_day(p_space_id,a,today_date,profile_tz); target_minutes:=public.personal_goal_minutes(p_space_id,a,today_date); tomorrow_target:=public.personal_goal_minutes(p_space_id,a,today_date+1); streak:=public.current_streak_days(p_space_id,a,profile_tz,snapshot_at);
 select exists(select 1 from public.focus_sessions s where s.user_id=a and (s.started_at at time zone profile_tz)::date=today_date) into today_locked;
 today_source:=case when exists(select 1 from public.personal_focus_goal_overrides o where o.user_id=a and o.goal_date=today_date) then 'today_override' when exists(select 1 from public.personal_focus_goal_defaults d where d.user_id=a and d.effective_from<=today_date) then 'personal_default' else 'space_default' end;
 select public.goal_json(id) into active_goal from public.goals where space_id=p_space_id and status='active' order by ends_at,id limit 1;
 return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sp.id,'name',sp.name,'timezone',sp.timezone,'active_member_count',active_count,'member_limit',sp.member_limit,'daily_checkin_target_minutes',sp.daily_checkin_target_minutes),
 'me',jsonb_build_object('member_id',me.id,'display_name',me.display_name,'role',me.role,'profile_timezone',profile_tz),'my_session',case when my_sid is null then null else public.session_json(my_sid) end,'focusing_members',friends,
 'today',jsonb_build_object('local_date',today_date,'credited_focus_seconds',today_seconds,'checkin_target_seconds',target_minutes*60,'checkin_completed',today_seconds>=target_minutes*60,'current_streak_days',streak,'goal_target_minutes',target_minutes,'goal_source',today_source,'goal_locked',today_locked,'future_default_target_minutes',tomorrow_target),
 'active_goal_summary',active_goal,'unseen_achievement',(select jsonb_build_object('achievement_id',ac.id,'achievement_type',ac.achievement_type,'earned_at',ac.earned_at,'metadata',ac.metadata) from public.achievements ac left join public.achievement_reads ar on ar.achievement_id=ac.id and ar.member_id=me.id where ac.space_id=p_space_id and ar.achievement_id is null order by ac.earned_at limit 1)));
end $$;

create function private.evaluate_living_flame_day(p_space_id uuid,p_day date,p_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare tz text; day_start timestamptz; day_end timestamptz; window_start timestamptz; window_end timestamptz; gap_max interval; members uuid[];
begin
 select timezone into tz from public.spaces where id=p_space_id;
 day_start:=p_day::timestamp at time zone tz;
 day_end:=(p_day+1)::timestamp at time zone tz;
 with clipped as(
   select greatest(seg.started_at,day_start) started_at,least(seg.ended_at,day_end) ended_at
   from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id
   where s.space_id=p_space_id and s.status='completed' and s.started_at>=private.extended_achievements_enabled_at()
     and seg.ended_at is not null and seg.started_at<day_end and seg.ended_at>day_start
 ) select min(started_at),max(ended_at) into window_start,window_end from clipped where ended_at>started_at;
 if window_end-window_start<interval '1 hour' then return; end if;
 with clipped as(
   select greatest(seg.started_at,day_start) started_at,least(seg.ended_at,day_end) ended_at
   from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id
   where s.space_id=p_space_id and s.status='completed' and s.started_at>=private.extended_achievements_enabled_at()
     and seg.ended_at is not null and seg.started_at<day_end and seg.ended_at>day_start
 ), ordered as(
   select started_at,ended_at,max(ended_at) over(order by started_at,ended_at rows between unbounded preceding and 1 preceding) previous_end
   from clipped where ended_at>started_at
 ), marked as(select *,case when previous_end is null or started_at>previous_end then 1 else 0 end cut from ordered),
 grouped as(select *,sum(cut) over(order by started_at,ended_at) island from marked),
 merged as(select min(started_at) started_at,max(ended_at) ended_at from grouped group by island),
 gaps as(select ended_at,lead(started_at) over(order by started_at) next_start from merged)
 select coalesce(max(next_start-ended_at),interval '0') into gap_max from gaps;
 with clipped as(
   select s.member_id,greatest(seg.started_at,day_start) started_at,least(seg.ended_at,day_end) ended_at
   from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id
   where s.space_id=p_space_id and s.status='completed' and s.started_at>=private.extended_achievements_enabled_at()
     and seg.ended_at is not null and seg.started_at<day_end and seg.ended_at>day_start
 ) select array_agg(member_id order by member_id) into members from(
   select member_id from clipped where ended_at>started_at group by member_id
   having sum(ended_at-started_at)>=interval '30 minutes'
 ) qualifying;
 if gap_max<=interval '30 minutes' and cardinality(members)>=3 then
   perform private.record_shared_achievement_event(p_space_id,'living_flame','flame:'||p_day,least(p_at,window_end),'gold',
     jsonb_build_object('local_date',p_day,'window_start',window_start,'window_end',window_end,'maximum_gap_seconds',extract(epoch from gap_max)::integer),members);
 end if;
end $$;

create or replace function private.evaluate_shared_focus_achievements() returns trigger
language plpgsql security definer set search_path='' as $$
declare tz text; d date; r record; members uuid[]; window_start timestamptz; qualifies boolean; affected_day date;
begin
  if new.status<>'completed' or old.status in('completed','discarded') then return new; end if;
  if new.started_at<private.extended_achievements_enabled_at() then return new; end if;
  select timezone into tz from public.spaces where id=new.space_id; d:=(new.started_at at time zone tz)::date;

  with recursive candidates as(
    select s.id,s.member_id,s.started_at from public.focus_sessions s where s.space_id=new.space_id and s.status='completed'
      and s.started_at>=private.extended_achievements_enabled_at() and (s.started_at at time zone tz)::date=d
  ), cluster as(
    select id,member_id,started_at from candidates where id=new.id
    union
    select c.id,c.member_id,c.started_at from candidates c join cluster x on abs(extract(epoch from(c.started_at-x.started_at)))<=180
  ), member_set as(select array_agg(distinct member_id order by member_id) mids from cluster),
  points as(select seg.started_at t from cluster c join public.focus_segments seg on seg.session_id=c.id and seg.ended_at is not null union
    select seg.ended_at from cluster c join public.focus_segments seg on seg.session_id=c.id and seg.ended_at is not null),
  spans as(select t,lead(t) over(order by t) e from points), active as(
    select sp.t,sp.e from spans sp cross join member_set ms where sp.e>sp.t and(
      select count(distinct c.member_id) from cluster c join public.focus_segments seg on seg.session_id=c.id
      where seg.started_at<=sp.t and seg.ended_at>=sp.e)=cardinality(ms.mids)),
  marked as(select *,case when lag(e) over(order by t)=t then 0 else 1 end cut from active),
  islands as(select *,sum(cut) over(order by t) island from marked),
  durations as(select min(t) start_at,sum(e-t) duration from islands group by island)
  select ms.mids,coalesce(bool_or(duration>=interval '30 minutes'),false),min(start_at) filter(where duration>=interval '30 minutes')
    into members,qualifies,window_start from member_set ms left join durations on true group by ms.mids;
  if cardinality(members)>=2 and qualifies then
    perform private.record_shared_achievement_event(new.space_id,'chance_encounter','encounter:'||window_start||':'||array_to_string(members,','),new.completed_at,'gold',jsonb_build_object('local_date',d,'started_at',window_start),members);
  end if;

  for r in
    with points as(select seg.started_at t from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id where s.space_id=new.space_id and s.started_at>=private.extended_achievements_enabled_at() and seg.ended_at is not null union
      select seg.ended_at from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id where s.space_id=new.space_id and s.started_at>=private.extended_achievements_enabled_at() and seg.ended_at is not null),
    spans as(select t,lead(t) over(order by t) e from points), active as(
      select sp.t,sp.e,array_agg(distinct s.member_id order by s.member_id) mids from spans sp join public.focus_segments seg on seg.started_at<=sp.t and seg.ended_at>=sp.e
      join public.focus_sessions s on s.id=seg.session_id and s.space_id=new.space_id and s.started_at>=private.extended_achievements_enabled_at() where sp.e>sp.t group by sp.t,sp.e),
    marked as(select *,case when lag(e) over(partition by mids order by t)=t then 0 else 1 end cut from active where cardinality(mids)>=3),
    islands as(select *,sum(cut) over(partition by mids order by t) island from marked)
    select min(t) start_at,max(e) end_at,mids from islands group by mids,island having sum(e-t)>=interval '30 minutes'
  loop
    perform private.record_shared_achievement_event(new.space_id,'fellow_travelers','overlap:'||r.start_at||':'||array_to_string(r.mids,','),r.end_at,
      case when cardinality(r.mids)>=5 then 'gold' else 'silver' end,jsonb_build_object('member_count',cardinality(r.mids),'stage',case when cardinality(r.mids)>=5 then 5 else 3 end),r.mids);
  end loop;

  if new.accumulated_focus_seconds>=1800 then
    for r in select s.member_id,s.id,s.completed_at from public.focus_sessions s where s.space_id=new.space_id
      and s.member_id<>new.member_id and s.status='completed' and s.accumulated_focus_seconds>=1800
      and s.started_at>=private.extended_achievements_enabled_at() and new.started_at-s.completed_at between interval '0' and interval '5 minutes'
    loop
      perform private.record_shared_achievement_event(new.space_id,'focus_relay',
        'relay:'||d||':'||least(r.member_id,new.member_id)||':'||greatest(r.member_id,new.member_id),
        new.completed_at,'gold',jsonb_build_object('local_date',d),array[r.member_id,new.member_id]);
    end loop;
  end if;

  for affected_day in
    select generate_series(
      (min(seg.started_at) at time zone tz)::date,
      ((max(seg.ended_at)-interval '1 microsecond') at time zone tz)::date,
      interval '1 day'
    )::date from public.focus_segments seg where seg.session_id=new.id and seg.ended_at is not null
  loop
    perform private.evaluate_living_flame_day(new.space_id,affected_day,new.completed_at);
  end loop;
  return new;
end $$;

revoke all on function private.rpc_impl_start_focus(uuid,text,text,text,uuid) from public,anon,authenticated;
revoke all on function private.evaluate_living_flame_day(uuid,date,timestamptz) from public,anon,authenticated;
revoke all on function public.start_focus(uuid,text,text,text,uuid) from public,anon;
grant execute on function public.start_focus(uuid,text,text,text,uuid) to authenticated;
