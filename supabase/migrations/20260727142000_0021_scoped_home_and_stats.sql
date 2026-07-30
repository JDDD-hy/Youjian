create index focus_sessions_active_space on public.focus_sessions(space_id,status,started_at)
 where status in('focusing','paused');
create index focus_sessions_completed_space_id on public.focus_sessions(space_id,id)
 where status='completed';
create index focus_sessions_completed_space_user_id on public.focus_sessions(space_id,user_id,id)
 where status='completed';

create function private.run_space_goal_maintenance(p_space_id uuid,p_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; progress jsonb; expired int:=0; activated int:=0; missed int:=0; resolved int:=0; awards int:=0; tz text; d date; target int; all_done boolean; threshold int;
begin
 update public.goal_proposals set status='expired',resolved_at=p_at where space_id=p_space_id and status='pending' and expires_at<=p_at; get diagnostics expired=row_count;
 update public.goals set status='failed',completed_at=ends_at where space_id=p_space_id and status='scheduled' and ends_at<=p_at; get diagnostics missed=row_count;
 update public.goals set status='active' where space_id=p_space_id and status='scheduled' and starts_at<=p_at and ends_at>p_at; get diagnostics activated=row_count;
 for r in select * from public.goals where space_id=p_space_id and status='active' for update skip locked loop
  progress:=public.goal_progress_json(r.id,p_at);
  if(progress->>'completed')::boolean then update public.goals set status='completed',completed_at=p_at where id=r.id; resolved:=resolved+1;
  elsif r.ends_at<=p_at then update public.goals set status='failed',completed_at=r.ends_at where id=r.id; resolved:=resolved+1; end if;
 end loop;
 select timezone,daily_checkin_target_minutes*60 into tz,target from public.spaces where id=p_space_id;
 insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
 select g.space_id,'first_goal','first-goal',g.completed_at,jsonb_build_object('goal_id',g.id) from public.goals g
 where g.id=(select id from public.goals where space_id=p_space_id and status='completed' order by completed_at,id limit 1)
 on conflict(space_id,dedupe_key) do nothing; get diagnostics awards=row_count;
 for d in select(p_at at time zone tz)::date union select(p_at at time zone tz)::date-1 loop
  select count(*)>1 and bool_and(public.credited_seconds_for_day(p_space_id,m.user_id,d,tz)>=target) into all_done
  from public.space_members m where m.space_id=p_space_id and m.status='active';
  if all_done then insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
   values(p_space_id,'together_lit','together-lit:'||d,p_at,jsonb_build_object('local_date',d)) on conflict do nothing; end if;
 end loop;
 if not exists(select 1 from generate_series(0,2)n where not exists(select 1 from public.achievements a where a.space_id=p_space_id and a.dedupe_key='together-lit:'||((p_at at time zone tz)::date-n)::text)) then
  insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
  values(p_space_id,'three_days_together','three-days:'||((p_at at time zone tz)::date),p_at,jsonb_build_object('period_end_date',(p_at at time zone tz)::date)) on conflict do nothing;
 end if;
 foreach threshold in array array[600,3000,6000] loop
  if(select coalesce(sum(accumulated_focus_seconds),0) from public.focus_sessions where space_id=p_space_id and status='completed')>=threshold::bigint*60 then
   insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
   values(p_space_id,'focus_milestone','milestone:'||threshold,p_at,jsonb_build_object('threshold_minutes',threshold)) on conflict do nothing;
  end if;
 end loop;
 return jsonb_build_object('expired_proposals',expired,'activated_goals',activated,'missed_goals',missed,'resolved_goals',resolved,'awards',awards);
end $$;

create function private.run_space_maintenance(p_space_id uuid,p_at timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; settled int:=0; uncertain int:=0; goals jsonb;
begin
 for r in select id from public.focus_sessions where space_id=p_space_id and status in('focusing','paused') for update skip locked loop
  perform public.settle_session(r.id,p_at); settled:=settled+1;
 end loop;
 for r in select id,last_seen_at from public.focus_sessions where space_id=p_space_id and status='focusing' and last_seen_at+interval '120 seconds'<=p_at for update skip locked loop
  if not exists(select 1 from public.focus_connection_intervals where session_id=r.id and ended_at is null) then
   insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(r.id,r.last_seen_at+interval '120 seconds',r.last_seen_at);
   perform public.record_focus_event(r.id,null,'connection_unconfirmed',r.last_seen_at+interval '120 seconds');
   update public.focus_sessions set version=version+1 where id=r.id; uncertain:=uncertain+1;
  end if;
 end loop;
 goals:=private.run_space_goal_maintenance(p_space_id,p_at);
 return jsonb_build_object('settled_sessions',settled,'new_unconfirmed_intervals',uncertain,'goal_maintenance',goals,'ran_at',p_at);
end $$;
revoke all on function private.run_space_goal_maintenance(uuid,timestamptz),private.run_space_maintenance(uuid,timestamptz) from public,anon,authenticated;

create or replace function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); sp public.spaces%rowtype; me public.space_members%rowtype; my_sid uuid; friends jsonb; today_seconds int; streak int; today_date date; profile_tz text; active_count int; active_goal jsonb; snapshot_at timestamptz:=now();
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into sp from public.spaces where id=p_space_id; select * into me from public.space_members where space_id=p_space_id and user_id=a and status='active'; select timezone into profile_tz from public.profiles where id=a;
 perform private.run_space_maintenance(p_space_id,snapshot_at);
 select id into my_sid from public.focus_sessions where user_id=a and status in('focusing','paused'); select count(*) into active_count from public.space_members where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name,'session_id',s.id,'task_name',s.task_name,'category',s.category,'status',s.status,'accumulated_focus_seconds',s.accumulated_focus_seconds,'active_segment_started_at',s.active_segment_started_at,'connection',jsonb_build_object('status',case when snapshot_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,'last_seen_at',s.last_seen_at))order by m.joined_at),'[]') into friends
 from public.focus_sessions s join public.space_members m on m.id=s.member_id where s.space_id=p_space_id and s.user_id<>a and s.status='focusing' and m.status='active';
 today_date:=(snapshot_at at time zone profile_tz)::date; today_seconds:=public.credited_seconds_for_day(p_space_id,a,today_date,profile_tz); streak:=public.current_streak_days(p_space_id,a,profile_tz,snapshot_at);
 select public.goal_json(id) into active_goal from public.goals where space_id=p_space_id and status='active' order by ends_at,id limit 1;
 return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sp.id,'name',sp.name,'timezone',sp.timezone,'active_member_count',active_count,'member_limit',sp.member_limit,'daily_checkin_target_minutes',sp.daily_checkin_target_minutes),
 'me',jsonb_build_object('member_id',me.id,'display_name',me.display_name,'role',me.role,'profile_timezone',profile_tz),'my_session',case when my_sid is null then null else public.session_json(my_sid) end,'focusing_members',friends,
 'today',jsonb_build_object('credited_focus_seconds',today_seconds,'checkin_target_seconds',sp.daily_checkin_target_minutes*60,'checkin_completed',today_seconds>=sp.daily_checkin_target_minutes*60,'current_streak_days',streak),
 'active_goal_summary',active_goal,'unseen_achievement',(select jsonb_build_object('achievement_id',ac.id,'achievement_type',ac.achievement_type,'earned_at',ac.earned_at,'metadata',ac.metadata) from public.achievements ac left join public.achievement_reads ar on ar.achievement_id=ac.id and ar.member_id=me.id where ac.space_id=p_space_id and ar.achievement_id is null order by ac.earned_at limit 1)));
end $$;

create or replace function private.rpc_impl_get_stats_summary(p_space_id uuid,p_view text,p_period text,p_anchor_local_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); tz text; local_start date; local_end date; utc_start timestamptz; utc_end timestamptz; target int; days jsonb; total int; checkins int; sessions int;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_view not in('mine','space') then return public.api_error('INVALID_VIEW'); end if;
 if p_period not in('daily','weekly','monthly') then return public.api_error('INVALID_PERIOD'); end if;
 if p_anchor_local_date is null or p_anchor_local_date<date '2000-01-01' or p_anchor_local_date>date '2100-12-31' then return public.api_error('INVALID_DATE'); end if;
 if p_view='mine' then select timezone into tz from public.profiles where id=a; else select timezone into tz from public.spaces where id=p_space_id; end if;
 if p_period='daily' then local_start:=p_anchor_local_date; local_end:=local_start+1;
 elsif p_period='weekly' then local_start:=date_trunc('week',p_anchor_local_date::timestamp)::date; local_end:=local_start+7;
 else local_start:=date_trunc('month',p_anchor_local_date::timestamp)::date; local_end:=(local_start+interval '1 month')::date; end if;
 utc_start:=local_start::timestamp at time zone tz; utc_end:=local_end::timestamp at time zone tz;
 select daily_checkin_target_minutes*60 into target from public.spaces where id=p_space_id;
 with day_bounds as(
  select d::date local_date,d::date::timestamp at time zone tz lo,(d::date+1)::timestamp at time zone tz hi from generate_series(local_start,local_end-1,interval '1 day') d
 ),aggregated as(
  select b.local_date,floor(sum(extract(epoch from(least(g.ended_at,b.hi)-greatest(g.started_at,b.lo)))))::int seconds
  from day_bounds b join public.focus_segments g on g.ended_at>b.lo and g.started_at<b.hi
  join public.focus_sessions s on s.id=g.session_id and s.space_id=p_space_id and s.status='completed' and(p_view='space' or s.user_id=a)
  group by b.local_date
 ),day_values as(select b.local_date,coalesce(x.seconds,0) seconds from day_bounds b left join aggregated x using(local_date))
 select coalesce(jsonb_agg(jsonb_build_object('local_date',local_date,'credited_focus_seconds',seconds,'checkin_completed',seconds>=target) order by local_date),'[]'),coalesce(sum(seconds),0)::int,count(*) filter(where seconds>=target)::int into days,total,checkins from day_values;
 select count(distinct s.id)::int into sessions from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
 where s.space_id=p_space_id and s.status='completed' and g.ended_at>utc_start and g.started_at<utc_end and(p_view='space' or s.user_id=a);
 return public.api_ok(jsonb_build_object('view',p_view,'period',p_period,'timezone',tz,'period_start',utc_start,'period_end',utc_end,'credited_focus_seconds',total,'valid_session_count',sessions,'checkin_day_count',checkins,'days',days));
end $$;

revoke all on function private.rpc_impl_get_home_snapshot(uuid),private.rpc_impl_get_stats_summary(uuid,text,text,date) from public,anon,authenticated;
