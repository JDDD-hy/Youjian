-- Per-user daily focus goals with immutable history and server-authoritative locking.

create table public.personal_focus_goal_defaults (
  user_id uuid not null references public.profiles(id) on delete cascade,
  effective_from date not null,
  target_minutes smallint not null check (target_minutes between 30 and 720),
  created_at timestamptz not null default now(),
  primary key (user_id, effective_from)
);

create table public.personal_focus_goal_overrides (
  user_id uuid not null references public.profiles(id) on delete cascade,
  goal_date date not null,
  target_minutes smallint not null check (target_minutes between 30 and 720),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, goal_date)
);

alter table public.personal_focus_goal_defaults enable row level security;
alter table public.personal_focus_goal_overrides enable row level security;
revoke all on public.personal_focus_goal_defaults, public.personal_focus_goal_overrides from public, anon, authenticated;

create function public.personal_goal_minutes(p_space_id uuid, p_user_id uuid, p_goal_date date)
returns integer language sql stable security definer set search_path='' as $$
  select coalesce(
    (select o.target_minutes::integer from public.personal_focus_goal_overrides o
      where o.user_id=p_user_id and o.goal_date=p_goal_date),
    (select d.target_minutes::integer from public.personal_focus_goal_defaults d
      where d.user_id=p_user_id and d.effective_from<=p_goal_date
      order by d.effective_from desc limit 1),
    (select s.daily_checkin_target_minutes::integer from public.spaces s where s.id=p_space_id)
  )
$$;

create or replace function public.current_streak_days(p_space_id uuid,p_user_id uuid,p_timezone text,p_at timestamptz default now()) returns integer
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p_at at time zone p_timezone)::date; target int; streak int:=0;
begin
 target:=public.personal_goal_minutes(p_space_id,p_user_id,d)*60;
 if public.credited_seconds_for_day(p_space_id,p_user_id,d,p_timezone)<target then d:=d-1; end if;
 loop
   target:=public.personal_goal_minutes(p_space_id,p_user_id,d)*60;
   exit when public.credited_seconds_for_day(p_space_id,p_user_id,d,p_timezone)<target;
   streak:=streak+1; d:=d-1;
 end loop;
 return streak;
end $$;

create function private.rpc_impl_set_personal_daily_goal(
  p_space_id uuid,p_scope text,p_target_minutes integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); tz text; local_date date; effective_date date; h text; cached jsonb; result jsonb; locked boolean;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_scope not in ('today','future_default') then return public.api_error('INVALID_DAILY_GOAL_SCOPE'); end if;
 if p_target_minutes is null or p_target_minutes<30 or p_target_minutes>720 then return public.api_error('INVALID_DAILY_GOAL_TARGET'); end if;
 select timezone into tz from public.profiles where id=a;
 if tz is null or not exists(select 1 from pg_catalog.pg_timezone_names where name=tz) then return public.api_error('INVALID_TIMEZONE'); end if;
 local_date:=(now() at time zone tz)::date;
 h:=encode(extensions.digest(convert_to(p_space_id::text||'|'||p_scope||'|'||p_target_minutes::text,'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'set_personal_daily_goal',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a::text,0));
 if p_scope='today' then
   select exists(select 1 from public.focus_sessions s where s.user_id=a and (s.started_at at time zone tz)::date=local_date) into locked;
   if locked then return public.api_error('DAILY_GOAL_LOCKED'); end if;
   insert into public.personal_focus_goal_overrides(user_id,goal_date,target_minutes)
   values(a,local_date,p_target_minutes) on conflict(user_id,goal_date) do update
     set target_minutes=excluded.target_minutes,updated_at=now();
   effective_date:=local_date;
 else
   effective_date:=local_date+1;
   insert into public.personal_focus_goal_defaults(user_id,effective_from,target_minutes)
   values(a,effective_date,p_target_minutes) on conflict(user_id,effective_from) do update
     set target_minutes=excluded.target_minutes,created_at=now();
 end if;
 result:=public.api_ok(jsonb_build_object('scope',p_scope,'target_minutes',p_target_minutes,'effective_date',effective_date));
 return public.store_command(a,p_idempotency_key,'set_personal_daily_goal',h,null,result);
end $$;

create function public.set_personal_daily_goal(p_space_id uuid,p_scope text,p_target_minutes integer,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin return private.rpc_impl_set_personal_daily_goal(p_space_id,p_scope,p_target_minutes,p_idempotency_key);
exception when others then return private.rpc_internal_error_envelope('set_personal_daily_goal',sqlstate); end $$;

create or replace function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); sp public.spaces%rowtype; me public.space_members%rowtype; my_sid uuid; friends jsonb; today_seconds int; streak int; today_date date; profile_tz text; active_count int; active_goal jsonb; snapshot_at timestamptz:=now(); target_minutes int; tomorrow_target int; today_locked boolean; today_source text;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into sp from public.spaces where id=p_space_id; select * into me from public.space_members where space_id=p_space_id and user_id=a and status='active'; select timezone into profile_tz from public.profiles where id=a;
 perform private.run_space_maintenance(p_space_id,snapshot_at);
 select id into my_sid from public.focus_sessions where user_id=a and status in('focusing','paused'); select count(*) into active_count from public.space_members where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name,'session_id',s.id,'task_name',s.task_name,'category',s.category,'task_history',private.focus_task_history_json(s.id),'status',s.status,'accumulated_focus_seconds',s.accumulated_focus_seconds,'active_segment_started_at',s.active_segment_started_at,'connection',jsonb_build_object('status',case when snapshot_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,'last_seen_at',s.last_seen_at))order by m.joined_at),'[]') into friends
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

create or replace function private.rpc_impl_get_stats_summary(p_space_id uuid,p_view text,p_period text,p_anchor_local_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare output jsonb; a uuid:=auth.uid(); rewritten_days jsonb; checkins int;
begin
 output:=private.legacy_get_stats_summary_without_space_context(p_space_id,p_view,p_period,p_anchor_local_date);
 if output->>'ok'='true' and p_view='mine' then
   select coalesce(jsonb_agg(jsonb_set(day_value,'{checkin_completed}',to_jsonb(
       (day_value->>'credited_focus_seconds')::integer >= public.personal_goal_minutes(p_space_id,a,(day_value->>'local_date')::date)*60
     ),true) order by day_value->>'local_date'),'[]'::jsonb),
     count(*) filter(where (day_value->>'credited_focus_seconds')::integer >= public.personal_goal_minutes(p_space_id,a,(day_value->>'local_date')::date)*60)::integer
   into rewritten_days,checkins from jsonb_array_elements(output#>'{data,days}') day_value;
   output:=jsonb_set(output,'{data,days}',rewritten_days,true);
   output:=jsonb_set(output,'{data,checkin_day_count}',to_jsonb(checkins),true);
 end if;
 if output->>'ok'='true' then output:=jsonb_set(output,'{data,space_id}',to_jsonb(p_space_id),true); end if;
 return output;
end $$;

revoke all on function public.personal_goal_minutes(uuid,uuid,date),private.rpc_impl_set_personal_daily_goal(uuid,text,integer,uuid),private.rpc_impl_get_stats_summary(uuid,text,text,date) from public,anon,authenticated;
revoke all on function public.set_personal_daily_goal(uuid,text,integer,uuid) from public;
grant execute on function public.set_personal_daily_goal(uuid,text,integer,uuid) to authenticated;
