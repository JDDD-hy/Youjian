-- Extended repeatable achievements, series summaries, diamond tier and nav badges.

create table public.achievement_rule_versions (
  version text primary key,
  enabled_at timestamptz not null default now()
);
insert into public.achievement_rule_versions(version) values('extended-v1');

alter table public.personal_achievements
  drop constraint personal_achievements_achievement_type_check,
  drop constraint personal_achievements_tier_check;
alter table public.personal_achievements
  add constraint personal_achievements_type_valid check(char_length(achievement_type) between 1 and 40),
  add constraint personal_achievements_tier_valid check(tier in('bronze','silver','gold','diamond')),
  add column seen_at timestamptz;

alter table public.personal_achievement_awards
  drop constraint personal_achievement_awards_achievement_type_check;
alter table public.personal_achievement_awards
  add constraint personal_achievement_awards_type_valid check(char_length(achievement_type) between 1 and 40),
  add column event_key text,
  add column local_date date,
  add column metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object');
update public.personal_achievement_awards set event_key=source_session_id::text where event_key is null;
alter table public.personal_achievement_awards alter column event_key set not null;
create unique index personal_achievement_awards_event_key
  on public.personal_achievement_awards(user_id,achievement_type,event_key);

create table public.achievement_nav_reads (
  member_id uuid primary key references public.space_members(id) on delete cascade,
  personal_seen_at timestamptz not null default '-infinity',
  shared_seen_at timestamptz not null default '-infinity'
);
alter table public.achievement_nav_reads enable row level security;
alter table public.achievement_rule_versions enable row level security;
revoke all on public.achievement_rule_versions,public.achievement_nav_reads from public,anon,authenticated;

create function private.extended_achievements_enabled_at() returns timestamptz
language sql stable security definer set search_path='' as $$
  select enabled_at from public.achievement_rule_versions where version='extended-v1'
$$;

create function private.personal_tier(p_type text,p_count integer,p_metadata jsonb)
returns text language sql immutable set search_path='' as $$
  select case
    when p_type='solo_focus' then case when p_count>=20 then 'gold' when p_count>=5 then 'silver' else 'bronze' end
    when p_type='promise_keeper' then case
      when coalesce((p_metadata->>'stage_days')::int,1)>=30 then 'diamond'
      when coalesce((p_metadata->>'stage_days')::int,1)>=7 then 'gold'
      when coalesce((p_metadata->>'stage_days')::int,1)>=3 then 'silver' else 'bronze' end
    else 'gold' end
$$;

create or replace function private.record_personal_achievement_event(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_event_key text,
  p_local_date date,p_earned_at timestamptz,p_metadata jsonb default '{}'::jsonb
) returns boolean language plpgsql security definer set search_path='' as $$
declare inserted_id uuid;
begin
  insert into public.personal_achievement_awards(
    user_id,achievement_type,source_space_id,source_session_id,event_key,local_date,earned_at,metadata
  ) values(p_user_id,p_type,p_space_id,p_session_id,p_event_key,p_local_date,p_earned_at,p_metadata)
  on conflict(user_id,achievement_type,event_key) do nothing returning id into inserted_id;
  if inserted_id is null then return false; end if;
  insert into public.personal_achievements(
    user_id,achievement_type,first_earned_at,last_earned_at,count,tier,metadata
  ) values(p_user_id,p_type,p_earned_at,p_earned_at,1,
    private.personal_tier(p_type,1,p_metadata),p_metadata)
  on conflict(user_id,achievement_type) do update set
    first_earned_at=least(public.personal_achievements.first_earned_at,excluded.first_earned_at),
    last_earned_at=greatest(public.personal_achievements.last_earned_at,excluded.last_earned_at),
    count=public.personal_achievements.count+1,
    metadata=case when excluded.achievement_type='promise_keeper' then
      jsonb_set(public.personal_achievements.metadata||excluded.metadata,'{stage_days}',
        to_jsonb(greatest(coalesce((public.personal_achievements.metadata->>'stage_days')::int,1),coalesce((excluded.metadata->>'stage_days')::int,1))))
      else public.personal_achievements.metadata||excluded.metadata end,
    tier=private.personal_tier(excluded.achievement_type,public.personal_achievements.count+1,
      case when excluded.achievement_type='promise_keeper' then
        jsonb_set(public.personal_achievements.metadata||excluded.metadata,'{stage_days}',
          to_jsonb(greatest(coalesce((public.personal_achievements.metadata->>'stage_days')::int,1),coalesce((excluded.metadata->>'stage_days')::int,1))))
        else public.personal_achievements.metadata||excluded.metadata end);
  return true;
end $$;

-- Keep the original award helper compatible with the richer event schema.
create or replace function private.record_personal_achievement(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_earned_at timestamptz
) returns boolean language sql security definer set search_path='' as $$
  select private.record_personal_achievement_event(
    p_user_id,p_type,p_space_id,p_session_id,p_session_id::text,
    (p_earned_at at time zone 'UTC')::date,p_earned_at,'{}'::jsonb
  )
$$;

create function private.user_credited_seconds_for_day(
  p_user_id uuid,p_day date,p_timezone text,p_since timestamptz default '-infinity'
) returns integer language sql stable security definer set search_path='' as $$
  select coalesce(floor(sum(extract(epoch from (
    least(g.ended_at,(p_day+1)::timestamp at time zone p_timezone)-
    greatest(g.started_at,p_day::timestamp at time zone p_timezone)
  )))),0)::integer
  from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
  where s.user_id=p_user_id and s.status='completed' and s.started_at>=p_since and g.ended_at is not null
    and g.started_at<(p_day+1)::timestamp at time zone p_timezone
    and g.ended_at>p_day::timestamp at time zone p_timezone
$$;

create function private.extended_personal_goal_streak(
  p_user_id uuid,p_space_id uuid,p_timezone text,p_day date
) returns integer language plpgsql stable security definer set search_path='' as $$
declare cursor_day date:=p_day; enabled timestamptz:=private.extended_achievements_enabled_at(); result int:=0;
begin
  while cursor_day>=(enabled at time zone p_timezone)::date loop
    exit when private.user_credited_seconds_for_day(p_user_id,cursor_day,p_timezone,enabled)
      <public.personal_goal_minutes(p_space_id,p_user_id,cursor_day)*60;
    result:=result+1;
    cursor_day:=cursor_day-1;
  end loop;
  return result;
end $$;

create or replace function private.evaluate_personal_focus_achievements() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  seconds int; local_start timestamp; local_end timestamp; d date; day_sessions int;
  category_count int; streak int; paused boolean; prior_valid boolean; had_history boolean; day_seconds int;
begin
  if new.status<>'completed' or old.status in('completed','discarded') then return new; end if;
  select coalesce(sum(extract(epoch from(ended_at-started_at))),0)::int into seconds
    from public.focus_segments where session_id=new.id and ended_at is not null;
  local_start:=new.started_at at time zone new.timezone_snapshot;
  local_end:=new.completed_at at time zone new.timezone_snapshot;
  d:=local_start::date;
  select exists(select 1 from public.focus_events where session_id=new.id and event_type='paused') into paused;

  if seconds>=3600 and extract(hour from local_start)=23 and local_end::date>d then
    perform private.record_personal_achievement_event(new.user_id,'night_owl',new.space_id,new.id,new.id::text,d,new.completed_at);
  end if;
  if new.started_at>=private.extended_achievements_enabled_at() and seconds>=3600 and extract(hour from local_start) between 5 and 6 then
    perform private.record_personal_achievement_event(new.user_id,'dawn_walker',new.space_id,new.id,new.id::text,d,new.completed_at);
  end if;
  if new.started_at>=private.extended_achievements_enabled_at() and seconds>=3600 and not paused then
    perform private.record_personal_achievement_event(new.user_id,'unbroken_focus',new.space_id,new.id,new.id::text,d,new.completed_at);
  end if;
  if seconds>=3600 and not exists(
    select 1 from public.focus_segments mine join public.focus_sessions os on os.space_id=new.space_id and os.user_id<>new.user_id
    join public.focus_segments other on other.session_id=os.id
    where mine.session_id=new.id and mine.ended_at is not null and other.started_at<mine.ended_at
      and coalesce(other.ended_at,new.completed_at)>mine.started_at
  ) then perform private.record_personal_achievement_event(new.user_id,'solo_focus',new.space_id,new.id,new.id::text,d,new.completed_at); end if;

  if new.started_at>=private.extended_achievements_enabled_at() and local_end::date=d then
    select count(*) into day_sessions from public.focus_sessions s
      where s.user_id=new.user_id and s.status='completed' and s.started_at>=private.extended_achievements_enabled_at()
        and (s.started_at at time zone s.timezone_snapshot)::date=d
        and (s.completed_at at time zone s.timezone_snapshot)::date=d
        and s.accumulated_focus_seconds>=1800;
    if day_sessions>=2 then perform private.record_personal_achievement_event(new.user_id,'double_focus',new.space_id,new.id,d::text,d,new.completed_at); end if;
    if day_sessions>=3 then perform private.record_personal_achievement_event(new.user_id,'triple_focus',new.space_id,new.id,d::text,d,new.completed_at); end if;
    select count(*) into category_count from (
      select s.category from public.focus_sessions s where s.user_id=new.user_id and s.status='completed'
        and s.started_at>=private.extended_achievements_enabled_at()
        and (s.started_at at time zone s.timezone_snapshot)::date=d
        and (s.completed_at at time zone s.timezone_snapshot)::date=d
      group by s.category having sum(s.accumulated_focus_seconds)>=1800
    ) cats;
    if category_count>=3 then perform private.record_personal_achievement_event(new.user_id,'three_categories',new.space_id,new.id,d::text,d,new.completed_at); end if;

    streak:=private.extended_personal_goal_streak(new.user_id,new.space_id,new.timezone_snapshot,d);
    if streak in(1,3,7,30) then
      perform private.record_personal_achievement_event(new.user_id,'promise_keeper',new.space_id,new.id,d::text||':'||streak,d,new.completed_at,
        jsonb_build_object('stage_days',streak));
    end if;
    select private.user_credited_seconds_for_day(new.user_id,d,new.timezone_snapshot,private.extended_achievements_enabled_at()) into day_seconds;
    if day_seconds>=3600 then
      select exists(select 1 from public.focus_sessions s where s.user_id=new.user_id and s.status='completed'
        and s.accumulated_focus_seconds>=300 and (s.completed_at at time zone new.timezone_snapshot)::date between d-7 and d-1)
      into prior_valid;
      select exists(select 1 from public.focus_sessions s where s.user_id=new.user_id and s.status='completed'
        and s.accumulated_focus_seconds>=300 and (s.completed_at at time zone new.timezone_snapshot)::date<d-7)
      into had_history;
      if had_history and not prior_valid then perform private.record_personal_achievement_event(new.user_id,'return_after_break',new.space_id,new.id,d::text,d,new.completed_at); end if;
    end if;
  end if;
  return new;
end $$;

create function private.record_shared_achievement_event(
  p_space_id uuid,p_type text,p_key text,p_at timestamptz,p_tier text,p_metadata jsonb,p_members uuid[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid; mid uuid;
begin
  insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata,tier,participants_recorded)
  values(p_space_id,p_type,p_key,p_at,p_metadata,p_tier,true)
  on conflict(space_id,dedupe_key) do nothing returning id into aid;
  if aid is null then return null; end if;
  foreach mid in array p_members loop
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select aid,id,display_name from public.space_members where id=mid on conflict do nothing;
  end loop;
  return aid;
end $$;

create function private.evaluate_shared_focus_achievements() returns trigger
language plpgsql security definer set search_path='' as $$
declare tz text; d date; r record; members uuid[]; window_start timestamptz; window_end timestamptz; gap_max interval; qualifies boolean;
begin
  if new.status<>'completed' or old.status in('completed','discarded') then return new; end if;
  if new.started_at<private.extended_achievements_enabled_at() then return new; end if;
  select timezone into tz from public.spaces where id=new.space_id; d:=(new.started_at at time zone tz)::date;

  -- Pair/chain encounter: connected start-time cluster, common effective overlap >=30m.
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

  -- Concurrent groups are derived from segment boundary windows.
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
    perform private.record_shared_achievement_event(new.space_id,'fellow_travelers',
      'overlap:'||r.start_at||':'||array_to_string(r.mids,','),r.end_at,
      case when cardinality(r.mids)>=5 then 'gold' else 'silver' end,
      jsonb_build_object('member_count',cardinality(r.mids),'stage',case when cardinality(r.mids)>=5 then 5 else 3 end),r.mids);
  end loop;

  -- Directed relay from a completed >=30m session to this session.
  if new.accumulated_focus_seconds>=1800 then
    for r in select s.member_id,s.id,s.completed_at from public.focus_sessions s where s.space_id=new.space_id
      and s.member_id<>new.member_id and s.status='completed' and s.accumulated_focus_seconds>=1800
      and s.started_at>=private.extended_achievements_enabled_at()
      and new.started_at-s.completed_at between interval '0' and interval '5 minutes'
    loop
      perform private.record_shared_achievement_event(new.space_id,'focus_relay',
        'relay:'||d||':'||r.member_id||':'||new.member_id,new.completed_at,'gold',jsonb_build_object('local_date',d),array[r.member_id,new.member_id]);
    end loop;
  end if;

  -- Day chain: >=1h window, no uncovered gap >30m, >=3 members with 30m each.
  select min(seg.started_at),max(seg.ended_at) into window_start,window_end from public.focus_segments seg
    join public.focus_sessions s on s.id=seg.session_id where s.space_id=new.space_id and seg.ended_at is not null
      and s.started_at>=private.extended_achievements_enabled_at()
      and (seg.started_at at time zone tz)::date=d;
  if window_end-window_start>=interval '1 hour' then
    with ordered as(
      select seg.started_at,seg.ended_at,max(seg.ended_at) over(order by seg.started_at,seg.ended_at rows between unbounded preceding and 1 preceding) previous_end
      from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id
      where s.space_id=new.space_id and s.started_at>=private.extended_achievements_enabled_at() and seg.ended_at is not null and (seg.started_at at time zone tz)::date=d),
    marked as(select *,case when previous_end is null or started_at>previous_end then 1 else 0 end cut from ordered),
    grouped as(select *,sum(cut) over(order by started_at,ended_at) island from marked),
    merged as(select min(started_at) started_at,max(ended_at) ended_at from grouped group by island),
    gaps as(select ended_at,lead(started_at) over(order by started_at) next_start from merged)
    select coalesce(max(next_start-ended_at),interval '0') into gap_max from gaps;
    select array_agg(member_id) into members from(
      select s.member_id from public.focus_segments seg join public.focus_sessions s on s.id=seg.session_id
      where s.space_id=new.space_id and s.started_at>=private.extended_achievements_enabled_at() and seg.ended_at is not null and (seg.started_at at time zone tz)::date=d
      group by s.member_id having sum(seg.ended_at-seg.started_at)>=interval '30 minutes') q;
    if gap_max<=interval '30 minutes' and cardinality(members)>=3 then
      perform private.record_shared_achievement_event(new.space_id,'living_flame','flame:'||d,window_end,'gold',jsonb_build_object('local_date',d),members);
    end if;
  end if;
  return new;
end $$;

create trigger focus_sessions_evaluate_shared_achievements
after update of status on public.focus_sessions for each row
when(old.status in('focusing','paused') and new.status='completed')
execute function private.evaluate_shared_focus_achievements();

create function private.rpc_impl_get_nav_notifications(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m uuid; personal_seen timestamptz;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  insert into public.achievement_nav_reads(member_id) values(m) on conflict do nothing;
  select personal_seen_at into personal_seen from public.achievement_nav_reads where member_id=m;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,
    'personal',exists(select 1 from public.personal_achievements where user_id=a and last_earned_at>personal_seen),
    'shared',exists(select 1 from public.achievements ac where ac.space_id=p_space_id
      and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=ac.id and ar.member_id=m)),
    'proposal',exists(select 1 from public.goal_proposal_members pm join public.goal_proposals p on p.id=pm.proposal_id
      where pm.member_id=m and pm.vote is null and p.status='pending')));
end $$;

create function public.get_nav_notifications(p_space_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin return private.rpc_impl_get_nav_notifications(p_space_id); exception when others then return private.rpc_internal_error_envelope('get_nav_notifications',sqlstate); end $$;

create function private.rpc_impl_mark_achievement_tab_seen(p_space_id uuid,p_tab text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m uuid;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_tab not in('personal','shared') then return public.api_error('INVALID_ACHIEVEMENT_TAB'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active';
  insert into public.achievement_nav_reads(member_id,personal_seen_at,shared_seen_at)
  values(m,case when p_tab='personal' then now() else '-infinity' end,case when p_tab='shared' then now() else '-infinity' end)
  on conflict(member_id) do update set
    personal_seen_at=case when p_tab='personal' then now() else public.achievement_nav_reads.personal_seen_at end,
    shared_seen_at=case when p_tab='shared' then now() else public.achievement_nav_reads.shared_seen_at end;
  if p_tab='shared' then
    insert into public.achievement_reads(achievement_id,member_id)
    select ac.id,m from public.achievements ac where ac.space_id=p_space_id
    on conflict(achievement_id,member_id) do nothing;
  end if;
  return public.api_ok(jsonb_build_object('tab',p_tab,'seen',true));
end $$;

create function public.mark_achievement_tab_seen(p_space_id uuid,p_tab text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin return private.rpc_impl_mark_achievement_tab_seen(p_space_id,p_tab); exception when others then return private.rpc_internal_error_envelope('mark_achievement_tab_seen',sqlstate); end $$;

revoke all on function private.extended_achievements_enabled_at(),private.personal_tier(text,integer,jsonb),
  private.user_credited_seconds_for_day(uuid,date,text,timestamptz),
  private.extended_personal_goal_streak(uuid,uuid,text,date),
  private.record_personal_achievement_event(uuid,text,uuid,uuid,text,date,timestamptz,jsonb),
  private.record_shared_achievement_event(uuid,text,text,timestamptz,text,jsonb,uuid[]),
  private.evaluate_shared_focus_achievements(),private.rpc_impl_get_nav_notifications(uuid),
  private.rpc_impl_mark_achievement_tab_seen(uuid,text)
from public,anon,authenticated;
revoke all on function public.get_nav_notifications(uuid),public.mark_achievement_tab_seen(uuid,text) from public;
grant execute on function public.get_nav_notifications(uuid),public.mark_achievement_tab_seen(uuid,text) to authenticated;
