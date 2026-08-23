-- The achievement wrappers still delegate the base home payload to this
-- legacy-named function. Keep its focusing-member projection aligned with
-- the frontend HomeSnapshot contract.
create or replace function private.legacy_get_home_snapshot_before_personal_achievements(
  p_space_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  a uuid:=private.current_principal_id();
  sp public.spaces%rowtype;
  me public.space_members%rowtype;
  my_sid uuid;
  friends jsonb;
  today_seconds integer;
  streak integer;
  today_date date;
  profile_tz text;
  active_count integer;
  active_goal jsonb;
  snapshot_at timestamptz:=now();
  target_minutes integer;
  tomorrow_target integer;
  today_locked boolean;
  today_source text;
begin
  if not public.current_user_is_active_member(p_space_id) then
    return public.api_error('SPACE_ACCESS_DENIED');
  end if;

  select * into sp from public.spaces where id=p_space_id;
  select * into me
  from public.space_members
  where space_id=p_space_id and user_id=a and status='active';
  select timezone into profile_tz from public.profiles where id=a;

  perform private.run_space_maintenance(p_space_id,snapshot_at);

  select id into my_sid
  from public.focus_sessions
  where user_id=a and status in('focusing','paused');
  select count(*) into active_count
  from public.space_members
  where space_id=p_space_id and status='active';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_id',m.id,
        'display_name',m.display_name,
        'session_id',s.id,
        'task_name',s.task_name,
        'category',s.category,
        'task_history',private.focus_task_history_json(s.id),
        'status',s.status,
        'timezone_snapshot',s.timezone_snapshot,
        'accumulated_focus_seconds',s.accumulated_focus_seconds,
        'active_segment_started_at',s.active_segment_started_at,
        'connection',jsonb_build_object(
          'status',case
            when snapshot_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed'
            else 'connected'
          end,
          'last_seen_at',s.last_seen_at
        )
      )
      order by m.joined_at
    ),
    '[]'
  ) into friends
  from public.focus_sessions s
  join public.space_members m on m.id=s.member_id
  where s.space_id=p_space_id
    and s.user_id<>a
    and s.status='focusing'
    and m.status='active';

  today_date:=(snapshot_at at time zone profile_tz)::date;
  today_seconds:=public.credited_seconds_for_day(p_space_id,a,today_date,profile_tz);
  target_minutes:=public.personal_goal_minutes(p_space_id,a,today_date);
  tomorrow_target:=public.personal_goal_minutes(p_space_id,a,today_date+1);
  streak:=public.current_streak_days(p_space_id,a,profile_tz,snapshot_at);

  select exists(
    select 1
    from public.focus_sessions s
    where s.user_id=a
      and (s.started_at at time zone profile_tz)::date=today_date
  ) into today_locked;

  today_source:=case
    when exists(
      select 1 from public.personal_focus_goal_overrides o
      where o.user_id=a and o.goal_date=today_date
    ) then 'today_override'
    when exists(
      select 1 from public.personal_focus_goal_defaults d
      where d.user_id=a and d.effective_from<=today_date
    ) then 'personal_default'
    else 'space_default'
  end;

  select public.goal_json(id) into active_goal
  from public.goals
  where space_id=p_space_id and status='active'
  order by ends_at,id
  limit 1;

  return public.api_ok(jsonb_build_object(
    'space',jsonb_build_object(
      'id',sp.id,
      'name',sp.name,
      'timezone',sp.timezone,
      'active_member_count',active_count,
      'member_limit',sp.member_limit,
      'daily_checkin_target_minutes',sp.daily_checkin_target_minutes
    ),
    'me',jsonb_build_object(
      'member_id',me.id,
      'display_name',me.display_name,
      'role',me.role,
      'profile_timezone',profile_tz
    ),
    'my_session',case when my_sid is null then null else public.session_json(my_sid) end,
    'focusing_members',friends,
    'today',jsonb_build_object(
      'local_date',today_date,
      'credited_focus_seconds',today_seconds,
      'checkin_target_seconds',target_minutes*60,
      'checkin_completed',today_seconds>=target_minutes*60,
      'current_streak_days',streak,
      'goal_target_minutes',target_minutes,
      'goal_source',today_source,
      'goal_locked',today_locked,
      'future_default_target_minutes',tomorrow_target
    ),
    'active_goal_summary',active_goal,
    'unseen_achievement',(
      select jsonb_build_object(
        'achievement_id',ac.id,
        'achievement_type',ac.achievement_type,
        'earned_at',ac.earned_at,
        'metadata',ac.metadata
      )
      from public.achievements ac
      left join public.achievement_reads ar
        on ar.achievement_id=ac.id and ar.member_id=me.id
      where ac.space_id=p_space_id and ar.achievement_id is null
      order by ac.earned_at
      limit 1
    )
  ));
end
$$;

revoke all on function private.legacy_get_home_snapshot_before_personal_achievements(uuid)
from public,anon,authenticated;
