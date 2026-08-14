-- Separate durable achievement events from unlock notifications.
-- Historical rows are retained. New writes use the repeatability rules below.

alter table public.achievements
  add column notification_eligible boolean not null default true;

alter table public.personal_achievement_awards
  add column notification_eligible boolean not null default true;

alter table public.personal_achievements
  add column last_unlocked_at timestamptz;

update public.personal_achievements
set last_unlocked_at=last_earned_at
where last_unlocked_at is null;

alter table public.personal_achievements
  alter column last_unlocked_at set not null;

-- together_lit is an internal daily fact, never a user-facing notification.
update public.achievements
set notification_eligible=false
where achievement_type='together_lit';

-- Existing living-flame rows are retained, but only the first historical
-- unlock remains notification-visible. Later historical daily repeats stay
-- available for audit/statistics without resurfacing as unread achievements.
with ranked as(
  select id,row_number() over(partition by space_id order by earned_at,id) as rn
  from public.achievements
  where achievement_type='living_flame'
)
update public.achievements a
set notification_eligible=(r.rn=1)
from ranked r
where a.id=r.id;

-- The same projection applies to historical non-series shared events. The
-- full event rows remain intact; only the first row stays user-visible.
with ranked as(
  select id,row_number() over(partition by space_id,achievement_type order by earned_at,id) as rn
  from public.achievements
  where achievement_type in('chance_encounter','focus_relay')
)
update public.achievements a
set notification_eligible=(r.rn=1)
from ranked r
where a.id=r.id;

-- Older personal writers could emit duplicate non-series rows. Preserve every
-- row for audit, but expose only the first historical occurrence and align the
-- derived unlock timestamp with that first occurrence.
with ranked as(
  select id,row_number() over(partition by user_id,achievement_type order by earned_at,id) as rn
  from public.personal_achievement_awards
  where achievement_type not in('solo_focus','promise_keeper')
)
update public.personal_achievement_awards a
set notification_eligible=(r.rn=1)
from ranked r
where a.id=r.id;

update public.personal_achievements pa
set last_unlocked_at=coalesce((
  select min(e.earned_at)
  from public.personal_achievement_awards e
  where e.user_id=pa.user_id
    and e.achievement_type=pa.achievement_type
    and e.notification_eligible
),pa.last_unlocked_at)
where pa.achievement_type not in('solo_focus','promise_keeper');

drop policy personal_achievements_select_own on public.personal_achievements;
create policy personal_achievements_select_own
on public.personal_achievements for select to authenticated
using (user_id=(select private.current_principal_id()));

drop policy personal_achievement_awards_select_own on public.personal_achievement_awards;
create policy personal_achievement_awards_select_own
on public.personal_achievement_awards for select to authenticated
using (user_id=(select private.current_principal_id()));

create index achievements_notification_eligible
  on public.achievements(space_id,earned_at desc,id desc)
  where notification_eligible;

create index personal_achievement_awards_notifications
  on public.personal_achievement_awards(user_id,earned_at desc,id desc)
  where notification_eligible;

create or replace function private.achievement_stage(
  p_type text,p_count integer,p_metadata jsonb
) returns integer
language sql immutable set search_path='' as $$
  select case
    when p_type='solo_focus' then case when p_count>=20 then 3 when p_count>=5 then 2 else 1 end
    when p_type='promise_keeper' then case
      when coalesce((p_metadata->>'stage_days')::integer,1)>=30 then 4
      when coalesce((p_metadata->>'stage_days')::integer,1)>=7 then 3
      when coalesce((p_metadata->>'stage_days')::integer,1)>=3 then 2 else 1 end
    when p_type='together_streak' then case when coalesce((p_metadata->>'days')::integer,0)>=7 then 3 when coalesce((p_metadata->>'days')::integer,0)>=3 then 2 else 1 end
    when p_type='goal_milestone' then case when coalesce((p_metadata->>'completed_goal_count')::integer,0)>=10 then 3 when coalesce((p_metadata->>'completed_goal_count')::integer,0)>=3 then 2 else 1 end
    when p_type='focus_milestone' then case when coalesce((p_metadata->>'threshold_minutes')::integer,0)>=6000 then 3 when coalesce((p_metadata->>'threshold_minutes')::integer,0)>=3000 then 2 when coalesce((p_metadata->>'threshold_minutes')::integer,0)>=600 then 1 else 0 end
    when p_type='fellow_travelers' then case when coalesce((p_metadata->>'member_count')::integer,0)>=5 then 2 else 1 end
    else 1
  end
$$;

create or replace function private.achievement_tier(p_type text,p_stage integer)
returns text
language sql immutable set search_path='' as $$
  select case
    when p_type='promise_keeper' and p_stage>=4 then 'diamond'
    when p_stage>=3 then 'gold'
    when p_stage>=2 then 'silver'
    else 'bronze'
  end
$$;

create or replace function private.personal_tier(p_type text,p_count integer,p_metadata jsonb)
returns text
language sql immutable set search_path='' as $$
  select case when p_type in('solo_focus','promise_keeper')
    then private.achievement_tier(p_type,private.achievement_stage(p_type,p_count,p_metadata))
    else 'gold' end
$$;

create or replace function private.record_personal_achievement_event(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_event_key text,
  p_local_date date,p_earned_at timestamptz,p_metadata jsonb default '{}'::jsonb
) returns boolean
language plpgsql security definer set search_path='' as $$
declare
  inserted_id uuid;
  prior_count integer:=0;
  prior_stage integer:=0;
  next_count integer;
  next_stage integer;
  notify boolean;
  prior_metadata jsonb;
  merged_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
begin
  if p_type not in('night_owl','dawn_walker','solo_focus','unbroken_focus','double_focus','triple_focus','three_categories','promise_keeper','return_after_break') then
    raise exception using errcode='22023',message='invalid personal achievement type';
  end if;

  -- The lock is per user/type, not per space: a user can complete sessions in
  -- different spaces concurrently while the summary remains serialized.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text||':'||p_type,140601)
  );

  if p_type not in('solo_focus','promise_keeper') and (
    exists(
      select 1 from public.personal_achievement_awards
      where user_id=p_user_id and achievement_type=p_type
    ) or exists(
      select 1 from public.personal_achievements
      where user_id=p_user_id and achievement_type=p_type
    )
  ) then
    return false;
  end if;

  select pa.count,private.achievement_stage(pa.achievement_type,pa.count,pa.metadata),pa.metadata
    into prior_count,prior_stage,prior_metadata
  from public.personal_achievements pa
  where pa.user_id=p_user_id and pa.achievement_type=p_type
  for update;
  prior_count:=coalesce(prior_count,0);
  prior_stage:=coalesce(prior_stage,0);
  merged_metadata:=coalesce(prior_metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb);
  if p_type='promise_keeper' then
    merged_metadata:=jsonb_set(merged_metadata,'{stage_days}',to_jsonb(greatest(
      coalesce((prior_metadata->>'stage_days')::integer,1),
      coalesce((p_metadata->>'stage_days')::integer,1)
    )));
  end if;
  next_count:=prior_count+1;
  next_stage:=private.achievement_stage(p_type,next_count,merged_metadata);
  notify:=p_type not in('solo_focus','promise_keeper') or next_stage>prior_stage;

  insert into public.personal_achievement_awards(
    user_id,achievement_type,source_space_id,source_session_id,event_key,
    local_date,earned_at,metadata,notification_eligible
  ) values(
    p_user_id,p_type,p_space_id,p_session_id,p_event_key,p_local_date,p_earned_at,
    coalesce(p_metadata,'{}'::jsonb),notify
  ) on conflict do nothing returning id into inserted_id;
  if inserted_id is null then return false; end if;

  insert into public.personal_achievements(
    user_id,achievement_type,first_earned_at,last_earned_at,last_unlocked_at,
    count,tier,metadata
  ) values(
    p_user_id,p_type,p_earned_at,p_earned_at,p_earned_at,1,
    private.personal_tier(p_type,1,coalesce(p_metadata,'{}'::jsonb)),coalesce(p_metadata,'{}'::jsonb)
  ) on conflict(user_id,achievement_type) do update set
    first_earned_at=least(public.personal_achievements.first_earned_at,excluded.first_earned_at),
    last_earned_at=greatest(public.personal_achievements.last_earned_at,excluded.last_earned_at),
    last_unlocked_at=case when notify then greatest(public.personal_achievements.last_unlocked_at,excluded.last_unlocked_at) else public.personal_achievements.last_unlocked_at end,
    count=public.personal_achievements.count+1,
    tier=private.personal_tier(excluded.achievement_type,public.personal_achievements.count+1,merged_metadata),
    metadata=merged_metadata;
  return true;
end $$;

create or replace function private.record_personal_achievement(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_earned_at timestamptz
) returns boolean
language sql security definer set search_path='' as $$
  select private.record_personal_achievement_event(
    p_user_id,p_type,p_space_id,p_session_id,p_session_id::text,
    (p_earned_at at time zone 'UTC')::date,p_earned_at,'{}'::jsonb
  )
$$;

create or replace function private.shared_achievement_tier(p_type text,p_stage integer)
returns text
language sql immutable set search_path='' as $$
  select case when p_type='fellow_travelers' and p_stage>=2 then 'gold'
    when p_type='fellow_travelers' then 'silver'
    when p_stage>=3 then 'gold' when p_stage=2 then 'silver' else 'bronze' end
$$;

create or replace function private.record_shared_achievement_event(
  p_space_id uuid,p_type text,p_key text,p_at timestamptz,p_tier text,p_metadata jsonb,p_members uuid[]
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  aid uuid;
  mid uuid;
  prior_stage integer:=0;
  next_stage integer:=private.achievement_stage(p_type,1,coalesce(p_metadata,'{}'::jsonb));
  notify boolean:=true;
  stored_tier text:=p_tier;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_space_id::text||':'||p_type,140602)
  );

  -- Re-read threshold facts after taking the serialization lock. This keeps
  -- concurrent goal/session completions from calculating a stale stage before
  -- the lock is acquired.
  if p_type='goal_milestone' then
    select count(*)::integer into next_stage from public.goals
    where space_id=p_space_id and status='completed';
    p_metadata:=coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('completed_goal_count',next_stage);
  elsif p_type='focus_milestone' then
    select floor(coalesce(sum(accumulated_focus_seconds),0)/60.0)::integer into next_stage
    from public.focus_sessions where space_id=p_space_id and status='completed';
    p_metadata:=coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('threshold_minutes',next_stage);
  end if;

  if p_type in('chance_encounter','focus_relay') and exists(
    select 1 from public.achievements where space_id=p_space_id and achievement_type=p_type
  ) then
    return null;
  end if;
  if p_type in('together_streak','goal_milestone','focus_milestone','fellow_travelers') then
    select coalesce(max(private.achievement_stage(a.achievement_type,1,a.metadata)),0)
      into prior_stage from public.achievements a
      where a.space_id=p_space_id and a.achievement_type=p_type;
    next_stage:=private.achievement_stage(p_type,1,coalesce(p_metadata,'{}'::jsonb));
    notify:=next_stage>prior_stage;
    stored_tier:=private.shared_achievement_tier(p_type,next_stage);
  elsif p_type='living_flame' then
    notify:=not exists(select 1 from public.achievements where space_id=p_space_id and achievement_type=p_type);
  end if;

  insert into public.achievements(
    space_id,achievement_type,dedupe_key,earned_at,metadata,tier,
    participants_recorded,notification_eligible
  ) values(
    p_space_id,p_type,p_key,p_at,coalesce(p_metadata,'{}'::jsonb),stored_tier,
    true,notify
  ) on conflict(space_id,dedupe_key) do nothing returning id into aid;
  if aid is null then return null; end if;

  foreach mid in array coalesce(p_members,'{}'::uuid[]) loop
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select aid,id,display_name from public.space_members where id=mid
    on conflict do nothing;
  end loop;
  return aid;
end $$;

-- Stop legacy maintenance code from creating new fixed-threshold rows. The
-- historical rows remain untouched; new milestone events use the helpers above.
create function private.guard_legacy_achievement_inserts() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  -- These compatibility facts are historical-only. The canonical helpers
  -- above own all new goal/streak milestone writes after this migration.
  if (new.achievement_type='first_goal' and new.dedupe_key like 'first-goal%')
    or (new.achievement_type='three_days_together' and new.dedupe_key like 'three-days:%') then
    new.notification_eligible:=false;
    return new;
  end if;
  if new.achievement_type='three_day_together' and new.dedupe_key like 'three-days:%' then
    new.notification_eligible:=false;
    return new;
  end if;
  if new.achievement_type='together_lit' then
    new.notification_eligible:=false;
    return new;
  end if;
  if (new.achievement_type='focus_milestone' and new.dedupe_key like 'milestone:%')
    or (new.achievement_type='goal_milestone' and new.dedupe_key like 'goal-count:%')
    or (new.achievement_type='together_streak' and new.dedupe_key in('together-streak:1','together-streak:3','together-streak:7')) then
    return null;
  end if;
  return new;
end $$;

create trigger achievements_guard_legacy_repeatability
before insert on public.achievements
for each row execute function private.guard_legacy_achievement_inserts();

create or replace function private.capture_achievement_participants() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  d date;
  tz text;
  streak integer;
  daily_members uuid[];
begin
  if new.achievement_type='together_lit' then
    d:=(new.metadata->>'local_date')::date;
    select timezone into tz from public.spaces where id=new.space_id;
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select new.id,m.id,m.display_name from public.space_members m
    where m.space_id=new.space_id
      and m.joined_at < (d::timestamp at time zone tz)
      and (m.disabled_at is null or m.disabled_at >= ((d+1)::timestamp at time zone tz))
    on conflict do nothing;
    update public.achievements set participants_recorded=true where id=new.id;

    select coalesce(array_agg(ap.member_id order by ap.member_id),'{}'::uuid[])
      into daily_members
    from public.achievement_participants ap where ap.achievement_id=new.id;
    with recursive run(day,days) as(
      select d,1
      union all
      select run.day-1,run.days+1
      from run
      where exists(
        select 1 from public.achievements a
        where a.space_id=new.space_id and a.achievement_type='together_lit'
          and (a.metadata->>'local_date')::date=run.day-1
      )
    ) select max(days) into streak from run;
    perform private.record_shared_achievement_event(
      new.space_id,'together_streak','together-streak-day:'||d,new.earned_at,'bronze',
      jsonb_build_object('days',coalesce(streak,1),'period_end_date',d),daily_members
    );
  elsif new.achievement_type='focus_milestone' then
    update public.achievements set tier=private.shared_achievement_tier(
      new.achievement_type,private.achievement_stage(new.achievement_type,1,new.metadata)
    ),participants_recorded=true where id=new.id;
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select new.id,m.id,m.display_name from public.space_members m
    where m.space_id=new.space_id and exists(
      select 1 from public.focus_sessions s where s.member_id=m.id and s.status='completed' and s.completed_at<=new.earned_at
    ) on conflict do nothing;
  elsif new.achievement_type in('first_goal','goal_milestone') then
    update public.achievements set participants_recorded=true where id=new.id;
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select new.id,m.id,m.display_name from public.space_members m
    where m.space_id=new.space_id and exists(
      select 1 from public.goals g join public.goal_participants gp on gp.goal_id=g.id
      where g.space_id=new.space_id and g.status='completed' and g.completed_at<=new.earned_at and gp.member_id=m.id
    ) on conflict do nothing;
  end if;
  return new;
end $$;

create or replace function private.award_goal_tiers() returns trigger
language plpgsql security definer set search_path='' as $$
declare completed_count integer; members uuid[];
begin
  if new.status<>'completed' or old.status='completed' then return new; end if;
  select count(*)::integer into completed_count from public.goals where space_id=new.space_id and status='completed';
  select coalesce(array_agg(gp.member_id order by gp.member_id),'{}'::uuid[]) into members
  from public.goal_participants gp where gp.goal_id=new.id;
  perform private.record_shared_achievement_event(
    new.space_id,'goal_milestone','goal:'||new.id,new.completed_at,'bronze',
    jsonb_build_object('completed_goal_count',completed_count),members
  );
  return new;
end $$;

create function private.record_focus_milestone_for_session() returns trigger
language plpgsql security definer set search_path='' as $$
declare total_minutes integer;
begin
  if new.status<>'completed' or old.status in('completed','discarded') then return new; end if;
  if new.started_at<private.extended_achievements_enabled_at() then return new; end if;
  select floor(coalesce(sum(accumulated_focus_seconds),0)/60.0)::integer into total_minutes
  from public.focus_sessions where space_id=new.space_id and status='completed';
  if total_minutes>0 then
    perform private.record_shared_achievement_event(
      new.space_id,'focus_milestone','focus-session:'||new.id,new.completed_at,'bronze',
      jsonb_build_object('threshold_minutes',total_minutes),array[new.member_id]
    );
  end if;
  return new;
end $$;

create trigger focus_sessions_record_focus_milestone
after update of status on public.focus_sessions
for each row when(old.status in('focusing','paused') and new.status='completed')
execute function private.record_focus_milestone_for_session();

create or replace function private.evaluate_living_flame_day(p_space_id uuid,p_day date,p_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare
  tz text; day_start timestamptz; day_end timestamptz; members uuid[];
  covered boolean:=false;
begin
  select timezone into tz from public.spaces where id=p_space_id;
  if tz is null then return; end if;
  day_start:=p_day::timestamp at time zone tz;
  day_end:=(p_day+1)::timestamp at time zone tz;

  -- The full-day condition is a half-open interval. This is DST-safe because
  -- day_start/day_end are local-midnight timestamptz values, not +24h math.
  with raw as(
    select s.member_id,greatest(g.started_at,day_start) started_at,least(g.ended_at,day_end) ended_at
    from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
    where s.space_id=p_space_id and s.status='completed'
      and s.started_at>=private.extended_achievements_enabled_at()
      and g.ended_at is not null and g.started_at<day_end and g.ended_at>day_start
  ), member_points as(
    select member_id,started_at t from raw where ended_at>started_at
    union select member_id,ended_at from raw where ended_at>started_at
  ), member_spans as(
    select member_id,t,lead(t) over(partition by member_id order by t) e from member_points
  ), member_active as(
    select member_id,t,e from member_spans where e>t and exists(
      select 1 from raw r where r.member_id=member_spans.member_id and r.started_at<=member_spans.t and r.ended_at>=member_spans.e
    )
  ), member_marked as(
    select *,case when lag(e) over(partition by member_id order by t)=t then 0 else 1 end cut from member_active
  ), member_grouped as(
    select *,sum(cut) over(partition by member_id order by t) island from member_marked
  ), member_merged as(
    select member_id,min(t) started_at,max(e) ended_at from member_grouped group by member_id,island
  ), eligible as(
    select member_id from member_merged group by member_id having sum(ended_at-started_at)>=interval '30 minutes'
  ), qualified as(
    select m.member_id,m.started_at,m.ended_at from member_merged m join eligible e using(member_id)
  ), points as(
    select started_at t from qualified union select ended_at from qualified
  ), spans as(
    select t,lead(t) over(order by t) e from points
  ), active as(
    select t,e from spans where e>t and exists(select 1 from qualified q where q.started_at<=spans.t and q.ended_at>=spans.e)
  ), marked as(
    select *,case when lag(e) over(order by t)=t then 0 else 1 end cut from active
  ), grouped as(
    select *,sum(cut) over(order by t) island from marked
  ), merged as(
    select min(t) started_at,max(e) ended_at from grouped group by island
  ), gaps as(
    select started_at,ended_at,lead(started_at) over(order by started_at) next_start from merged
  )
  select exists(select 1 from merged where started_at=day_start)
    and exists(select 1 from merged where ended_at=day_end)
    and not exists(select 1 from gaps where next_start is not null and next_start>ended_at)
    and (select count(*) from eligible)>=2,
    (select array_agg(member_id order by member_id) from eligible)
  into covered,members;

  if covered then
    perform private.record_shared_achievement_event(
      p_space_id,'living_flame','flame:'||p_day,
      greatest(day_start,least(p_at,day_end)),'gold',
      jsonb_build_object('local_date',p_day,'window_start',day_start,'window_end',day_end,
        'qualified_member_count',cardinality(members)),members
    );
  end if;
end $$;

create or replace function private.rpc_impl_list_personal_achievements(
  p_space_id uuid,p_limit integer,p_cursor text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); cursor_time timestamptz; cursor_type text; items jsonb; next_cursor text; v_seen_at timestamptz;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  select max(n.personal_seen_at) into v_seen_at from public.achievement_nav_reads n join public.space_members m on m.id=n.member_id where m.user_id=a;
  if p_cursor is not null then begin
    cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz;
    cursor_type:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2);
  exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
  with rows as(
    select pa.*,row_number() over(order by last_unlocked_at desc,achievement_type desc) rn
    from public.personal_achievements pa where user_id=a and(p_cursor is null or(last_unlocked_at,achievement_type)<(cursor_time,cursor_type))
    order by last_unlocked_at desc,achievement_type desc limit p_limit+1
  ), chosen as(select * from rows where rn<=p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',achievement_type,'achievement_type',achievement_type,'tier',tier,
    'earned_at',last_unlocked_at,'first_earned_at',first_earned_at,'last_earned_at',last_earned_at,
    'last_unlocked_at',last_unlocked_at,
    'repeatable',achievement_type in('solo_focus','promise_keeper'),
    'count',count,'metadata',metadata,'seen',coalesce(v_seen_at,'-infinity')>=last_unlocked_at,
    'events',(select coalesce(jsonb_agg(jsonb_build_object('earned_at',e.earned_at,'local_date',e.local_date,
      'source_space_id',e.source_space_id,'metadata',e.metadata,'notification_eligible',true,'is_unlock',true) order by e.earned_at desc),'[]'::jsonb)
      from public.personal_achievement_awards e where e.user_id=a and e.achievement_type=chosen.achievement_type and e.notification_eligible)
  ) order by last_unlocked_at desc,achievement_type desc),'[]'::jsonb),
  case when(select count(*) from rows)>p_limit then(select encode(convert_to(last_unlocked_at::text||'|'||achievement_type,'UTF8'),'base64') from chosen order by last_unlocked_at,achievement_type limit 1) end
  into items,next_cursor from chosen;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',next_cursor));
end $$;

create or replace function private.rpc_impl_list_achievements(p_space_id uuid,p_limit integer,p_cursor text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); m uuid; items jsonb;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  if p_cursor is not null then return public.api_error('INVALID_CURSOR'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  with raw as(
    select ac.*,case when achievement_type in('together_streak','three_days_together','three_day_together') then 'together_streak'
      when achievement_type in('goal_milestone','first_goal') then 'goal_milestone'
      when achievement_type='focus_milestone' then 'focus_milestone'
      when achievement_type='fellow_travelers' then 'fellow_travelers' else achievement_type end card_type,
      case tier when 'diamond' then 4 when 'gold' then 3 when 'silver' then 2 else 1 end tier_rank,
      row_number() over(partition by achievement_type order by earned_at,id) legacy_rank
    from public.achievements ac where space_id=p_space_id and achievement_type<>'together_lit'
  ), base as(
    select r.* from raw r where
      (r.achievement_type not in('three_days_together','three_day_together') or(r.legacy_rank=1 and not exists(select 1 from raw c where c.achievement_type='together_streak' and coalesce((c.metadata->>'days')::int,0)=3)))
      and(r.achievement_type<>'first_goal' or(r.legacy_rank=1 and not exists(select 1 from raw c where c.achievement_type='goal_milestone' and coalesce((c.metadata->>'completed_goal_count')::int,0)=1)))
      and(r.card_type<>'focus_milestone' or private.achievement_stage('focus_milestone',1,r.metadata)>0)
  ), ranked as(
    select b.*,row_number() over(partition by card_type order by notification_eligible desc,tier_rank desc,earned_at desc,id desc) pick,
      count(*) over(partition by card_type) event_count,min(earned_at) over(partition by card_type) first_at,max(earned_at) over(partition by card_type) last_at
      ,max(earned_at) filter(where notification_eligible) over(partition by card_type) last_unlock_at
    from base b
  ), cards as(select * from ranked where pick=1 and last_unlock_at is not null order by last_unlock_at desc limit p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',case when card_type in('together_streak','goal_milestone','focus_milestone','fellow_travelers','chance_encounter','focus_relay','living_flame') then card_type else id::text end,
    'achievement_type',card_type,'tier',tier,'earned_at',last_unlock_at,'first_earned_at',first_at,'last_earned_at',last_at,'last_unlocked_at',last_unlock_at,
    'repeatable',card_type in('together_streak','goal_milestone','focus_milestone','fellow_travelers','living_flame'),'count',event_count,'metadata',metadata,
    'participants_recorded',true,
    'seen',not exists(select 1 from base unread where unread.card_type=cards.card_type and unread.notification_eligible and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=unread.id and ar.member_id=m)),
    'participants',(select coalesce(jsonb_agg(jsonb_build_object('member_id',ap.member_id,'display_name',ap.display_name_snapshot,'participation_days',ap.participation_days) order by ap.display_name_snapshot),'[]'::jsonb) from public.achievement_participants ap where ap.achievement_id=cards.id),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('achievement_id',ev.id,'earned_at',ev.earned_at,'metadata',ev.metadata,'notification_eligible',true,'is_unlock',true,'participants',(select coalesce(jsonb_agg(jsonb_build_object('member_id',ep.member_id,'display_name',ep.display_name_snapshot,'participation_days',ep.participation_days) order by ep.display_name_snapshot),'[]'::jsonb) from public.achievement_participants ep where ep.achievement_id=ev.id)) order by ev.earned_at desc),'[]'::jsonb) from base ev where ev.card_type=cards.card_type and ev.notification_eligible)
  ) order by last_unlock_at desc),'[]'::jsonb) into items from cards;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',null));
end $$;

create or replace function private.rpc_impl_get_nav_notifications(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); m uuid; personal_seen timestamptz;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  insert into public.achievement_nav_reads(member_id) values(m) on conflict do nothing;
  select personal_seen_at into personal_seen from public.achievement_nav_reads where member_id=m;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,
    'personal',exists(select 1 from public.personal_achievements where user_id=a and last_unlocked_at>personal_seen),
    'shared',exists(select 1 from public.achievements ac where ac.space_id=p_space_id and ac.achievement_type not in('first_goal','three_days_together','three_day_together') and ac.notification_eligible and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=ac.id and ar.member_id=m)),
    'proposal',exists(select 1 from public.goal_proposal_members pm join public.goal_proposals p on p.id=pm.proposal_id where pm.member_id=m and pm.vote is null and p.status='pending')));
end $$;

create or replace function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; a uuid:=private.current_principal_id(); m uuid; v_seen_at timestamptz; personal jsonb; shared jsonb;
begin
  result:=private.legacy_get_home_snapshot_before_personal_achievements(p_space_id);
  if result->>'ok'<>'true' then return result; end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  select jsonb_build_object('achievement_id',ac.id,'achievement_type',ac.achievement_type,'earned_at',ac.earned_at,'metadata',ac.metadata)
    into shared from public.achievements ac where ac.space_id=p_space_id and ac.achievement_type not in('first_goal','three_days_together','three_day_together') and ac.notification_eligible
      and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=ac.id and ar.member_id=m)
    order by ac.earned_at limit 1;
  result:=jsonb_set(result,'{data,unseen_achievement}',coalesce(shared,'null'::jsonb),true);
  select max(n.personal_seen_at) into v_seen_at from public.achievement_nav_reads n join public.space_members sm on sm.id=n.member_id where sm.user_id=a;
  select jsonb_build_object('achievement_id',pa.achievement_type,'achievement_type',pa.achievement_type,'tier',pa.tier,'earned_at',pa.last_unlocked_at,'first_earned_at',pa.first_earned_at,'last_earned_at',pa.last_earned_at,'count',pa.count,'metadata',pa.metadata,'seen',false)
    into personal from public.personal_achievements pa where pa.user_id=a and pa.last_unlocked_at>coalesce(v_seen_at,'-infinity') order by pa.last_unlocked_at limit 1;
  return jsonb_set(result,'{data,unseen_personal_achievement}',coalesce(personal,'null'::jsonb),true);
end $$;

revoke all on function private.achievement_stage(text,integer,jsonb),private.achievement_tier(text,integer),private.personal_tier(text,integer,jsonb),
  private.record_personal_achievement_event(uuid,text,uuid,uuid,text,date,timestamptz,jsonb),private.record_personal_achievement(uuid,text,uuid,uuid,timestamptz),
  private.shared_achievement_tier(text,integer),private.record_shared_achievement_event(uuid,text,text,timestamptz,text,jsonb,uuid[]),
  private.guard_legacy_achievement_inserts(),private.capture_achievement_participants(),private.award_goal_tiers(),
  private.record_focus_milestone_for_session(),private.evaluate_living_flame_day(uuid,date,timestamptz),
  private.rpc_impl_list_personal_achievements(uuid,integer,text),private.rpc_impl_list_achievements(uuid,integer,text),
  private.rpc_impl_get_nav_notifications(uuid),private.rpc_impl_get_home_snapshot(uuid)
from public,anon,authenticated;

-- RLS policies need to resolve the caller's stable principal while remaining
-- unavailable to anonymous callers.
grant execute on function private.current_principal_id() to authenticated;

revoke all on function public.get_nav_notifications(uuid),public.mark_achievement_tab_seen(uuid,text) from public,anon;
grant execute on function public.get_nav_notifications(uuid),public.mark_achievement_tab_seen(uuid,text) to authenticated;
