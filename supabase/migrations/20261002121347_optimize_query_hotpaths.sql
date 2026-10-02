-- Cache names only; UTC offsets and DST are still resolved by PostgreSQL.
-- A daily concurrent refresh picks up tzdata changes without blocking readers.
create materialized view private.iana_timezones as
select name from pg_catalog.pg_timezone_names;
create unique index iana_timezones_name on private.iana_timezones(name);
revoke all on private.iana_timezones from public,anon,authenticated;

select cron.schedule(
  'youjian-timezone-cache-refresh',
  '17 3 * * *',
  'refresh materialized view concurrently private.iana_timezones'
);

create or replace function public.validate_iana_timezone(p_timezone text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.iana_timezones where name=p_timezone)
$$;
revoke all on function public.validate_iana_timezone(text) from public,anon,authenticated;

-- Supports retention cleanup and the monitor's latest-run lookup.
create index maintenance_runs_started_at on private.maintenance_runs(started_at,id);

CREATE OR REPLACE FUNCTION private.rpc_impl_set_personal_daily_goal(p_space_id uuid, p_scope text, p_target_minutes integer, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a uuid:=private.current_principal_id(); tz text; local_date date; effective_date date; h text; cached jsonb; result jsonb; locked boolean;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_scope not in ('today','future_default') then return public.api_error('INVALID_DAILY_GOAL_SCOPE'); end if;
 if p_target_minutes is null or p_target_minutes<30 or p_target_minutes>720 then return public.api_error('INVALID_DAILY_GOAL_TARGET'); end if;
 select timezone into tz from public.profiles where id=a;
 if not public.validate_iana_timezone(tz) then return public.api_error('INVALID_TIMEZONE'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION private.rpc_impl_set_personal_deadline(p_title text, p_target_date date, p_timezone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid:=private.current_principal_id();
  normalized_title text:=btrim(p_title);
  local_today date;
  deadline public.personal_deadlines%rowtype;
begin
  if actor is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_title is null or char_length(normalized_title) not between 1 and 40 then
    return public.api_error('INVALID_DEADLINE_TITLE');
  end if;
  if not public.validate_iana_timezone(p_timezone) then
    return public.api_error('INVALID_TIMEZONE');
  end if;

  local_today:=(pg_catalog.clock_timestamp() at time zone p_timezone)::date;
  if p_target_date is null or p_target_date<local_today then
    return public.api_error('INVALID_DEADLINE_DATE');
  end if;

  insert into public.personal_deadlines(user_id,title,target_date)
  values(actor,normalized_title,p_target_date)
  on conflict(user_id) do update set
    title=excluded.title,
    target_date=excluded.target_date,
    updated_at=pg_catalog.clock_timestamp()
  returning * into deadline;

  return public.api_ok(jsonb_build_object(
    'deadline',private.personal_deadline_json(deadline)
  ));
end $function$;

CREATE OR REPLACE FUNCTION private.run_space_goal_maintenance_before_missed_goal_fix(p_space_id uuid, p_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; progress jsonb; expired int:=0; activated int:=0; missed int:=0; resolved int:=0; awards int:=0; tz text; d date; target int; all_done boolean;
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
 for d in
    select days.day
    from (values ((p_at at time zone tz)::date),((p_at at time zone tz)::date-1)) days(day)
    where (select count(*) from public.space_members m where m.space_id=p_space_id and m.status='active')>1
      and not exists(select 1 from public.achievements a where a.space_id=p_space_id and a.dedupe_key='together-lit:'||days.day)
    order by days.day
  loop
  select count(*)>1 and bool_and(public.credited_seconds_for_day(p_space_id,m.user_id,d,tz)>=target) into all_done
  from public.space_members m where m.space_id=p_space_id and m.status='active';
  if all_done then insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
   values(p_space_id,'together_lit','together-lit:'||d,p_at,jsonb_build_object('local_date',d)) on conflict do nothing; end if;
 end loop;
 if not exists(select 1 from generate_series(0,2)n where not exists(select 1 from public.achievements a where a.space_id=p_space_id and a.dedupe_key='together-lit:'||((p_at at time zone tz)::date-n)::text)) then
  insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
  values(p_space_id,'three_days_together','three-days:'||((p_at at time zone tz)::date),p_at,jsonb_build_object('period_end_date',(p_at at time zone tz)::date)) on conflict do nothing;
 end if;
 -- Fixed milestone inserts are discarded by guard_legacy_achievement_inserts;
 -- canonical milestones are awarded by the existing completion triggers.
 return jsonb_build_object('expired_proposals',expired,'activated_goals',activated,'missed_goals',missed,'resolved_goals',resolved,'awards',awards);
end $function$;

CREATE OR REPLACE FUNCTION public.run_goal_maintenance_before_missed_goal_fix(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; progress jsonb; expired int:=0; activated int:=0; missed int:=0; resolved int:=0; awards int:=0; tz text; d date; target int; all_done boolean;
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
  for d in
    select days.day
    from (values ((p_at at time zone tz)::date),((p_at at time zone tz)::date-1)) days(day)
    where (select count(*) from public.space_members m where m.space_id=r.id and m.status='active')>1
      and not exists(select 1 from public.achievements a where a.space_id=r.id and a.dedupe_key='together-lit:'||days.day)
    order by days.day
  loop
   select count(*)>1 and bool_and(public.credited_seconds_for_day(r.id,m.user_id,d,tz)>=target) into all_done from public.space_members m where m.space_id=r.id and m.status='active';
   if all_done then insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'together_lit','together-lit:'||d,p_at,jsonb_build_object('local_date',d)) on conflict do nothing; end if;
  end loop;
  if not exists(select 1 from generate_series(0,2)n where not exists(select 1 from public.achievements a where a.space_id=r.id and a.dedupe_key='together-lit:'||((p_at at time zone tz)::date-n)::text)) then
   insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata) values(r.id,'three_days_together','three-days:'||((p_at at time zone tz)::date),p_at,jsonb_build_object('period_end_date',(p_at at time zone tz)::date)) on conflict do nothing;
  end if;
 -- Fixed milestone inserts are discarded by guard_legacy_achievement_inserts;
 -- canonical milestones are awarded by the existing completion triggers.
 end loop;
 return jsonb_build_object('expired_proposals',expired,'activated_goals',activated,'missed_goals',missed,'resolved_goals',resolved,'awards',awards);
end $function$;
