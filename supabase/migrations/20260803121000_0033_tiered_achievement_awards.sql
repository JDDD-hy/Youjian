-- Keep daily facts internally, while exposing one bronze/silver/gold award per streak line.

create function private.validate_together_lit_achievement() returns trigger
language plpgsql security definer set search_path='' as $$
declare d date; tz text; target int; eligible_count int; all_done boolean;
begin
  if new.achievement_type<>'together_lit' then return new; end if;
  d:=(new.metadata->>'local_date')::date;
  select timezone,daily_checkin_target_minutes*60 into tz,target from public.spaces where id=new.space_id;
  select count(*),coalesce(bool_and(public.credited_seconds_for_day(new.space_id,m.user_id,d,tz)>=target),false)
  into eligible_count,all_done
  from public.space_members m
  where m.space_id=new.space_id
    and m.joined_at < (d::timestamp at time zone tz)
    and (m.disabled_at is null or m.disabled_at >= ((d+1)::timestamp at time zone tz));
  if eligible_count<2 or not all_done then return null; end if;
  return new;
end $$;

create function private.capture_achievement_participants() returns trigger
language plpgsql security definer set search_path='' as $$
declare d date; tz text; threshold_days int; start_date date;
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

    foreach threshold_days in array array[1,3,7] loop
      start_date:=d-threshold_days+1;
      if (select count(distinct (a.metadata->>'local_date')::date)
          from public.achievements a
          where a.space_id=new.space_id and a.achievement_type='together_lit'
            and (a.metadata->>'local_date')::date between start_date and d)=threshold_days then
        insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata,tier,participants_recorded)
        values(new.space_id,'together_streak','together-streak:'||threshold_days,new.earned_at,
          jsonb_build_object('days',threshold_days,'period_end_date',d),
          case threshold_days when 1 then 'bronze' when 3 then 'silver' else 'gold' end,true)
        on conflict(space_id,dedupe_key) do nothing;
        insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot,participation_days)
        select award.id,ap.member_id,max(ap.display_name_snapshot),count(distinct daily.id)::int
        from public.achievements award
        join public.achievements daily on daily.space_id=award.space_id and daily.achievement_type='together_lit'
          and (daily.metadata->>'local_date')::date between start_date and d
        join public.achievement_participants ap on ap.achievement_id=daily.id
        where award.space_id=new.space_id and award.dedupe_key='together-streak:'||threshold_days
        group by award.id,ap.member_id on conflict do nothing;
      end if;
    end loop;
  elsif new.achievement_type='focus_milestone' then
    update public.achievements set tier=case
      when (new.metadata->>'threshold_minutes')::int>=6000 then 'gold'
      when (new.metadata->>'threshold_minutes')::int>=3000 then 'silver'
      else 'bronze' end,participants_recorded=true where id=new.id;
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select new.id,m.id,m.display_name
    from public.space_members m where m.space_id=new.space_id and exists(
      select 1 from public.focus_sessions s where s.member_id=m.id and s.status='completed' and s.completed_at<=new.earned_at
    ) on conflict do nothing;
  elsif new.achievement_type in('first_goal','goal_milestone') then
    update public.achievements set participants_recorded=true where id=new.id;
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select new.id,m.id,m.display_name
    from public.space_members m where m.space_id=new.space_id and exists(
      select 1 from public.goals g join public.goal_participants gp on gp.goal_id=g.id
      where g.space_id=new.space_id and g.status='completed' and g.completed_at<=new.earned_at and gp.member_id=m.id
    ) on conflict do nothing;
  end if;
  return new;
end $$;

create trigger achievements_validate_together_lit
before insert on public.achievements for each row execute function private.validate_together_lit_achievement();
create trigger achievements_capture_participants
after insert on public.achievements for each row execute function private.capture_achievement_participants();

create function private.award_goal_tiers() returns trigger
language plpgsql security definer set search_path='' as $$
declare completed_count int; threshold_count int;
begin
  if new.status<>'completed' or old.status='completed' then return new; end if;
  select count(*) into completed_count from public.goals where space_id=new.space_id and status='completed';
  foreach threshold_count in array array[1,3,10] loop
    if completed_count>=threshold_count then
      insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata,tier)
      values(new.space_id,'goal_milestone','goal-count:'||threshold_count,new.completed_at,
        jsonb_build_object('completed_goal_count',threshold_count),
        case threshold_count when 1 then 'bronze' when 3 then 'silver' else 'gold' end)
      on conflict(space_id,dedupe_key) do nothing;
    end if;
  end loop;
  return new;
end $$;

create trigger goals_award_tiers
after update of status on public.goals for each row execute function private.award_goal_tiers();

-- Backfill goal tiers and participant provenance from facts that remain reliable.
insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata,tier)
select s.id,'goal_milestone','goal-count:'||t.threshold_count,
  (select g.completed_at from public.goals g where g.space_id=s.id and g.status='completed' order by g.completed_at,g.id offset t.threshold_count-1 limit 1),
  jsonb_build_object('completed_goal_count',t.threshold_count),t.tier
from public.spaces s cross join (values(1,'bronze'),(3,'silver'),(10,'gold')) t(threshold_count,tier)
where (select count(*) from public.goals g where g.space_id=s.id and g.status='completed')>=t.threshold_count
on conflict(space_id,dedupe_key) do nothing;

-- Existing focus milestones can be reconstructed from session ownership.
insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
select a.id,m.id,m.display_name
from public.achievements a join public.space_members m on m.space_id=a.space_id
where a.achievement_type='focus_milestone' and exists(
  select 1 from public.focus_sessions s where s.member_id=m.id and s.status='completed' and s.completed_at<=a.earned_at
) on conflict do nothing;
update public.achievements a set participants_recorded=true
where a.achievement_type='focus_milestone' and exists(select 1 from public.achievement_participants ap where ap.achievement_id=a.id);

-- Reconstruct legacy daily participant facts when membership intervals remain reliable.
insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
select a.id,m.id,m.display_name
from public.achievements a
join public.spaces sp on sp.id=a.space_id
join public.space_members m on m.space_id=a.space_id
where a.achievement_type='together_lit'
  and m.joined_at < (((a.metadata->>'local_date')::date)::timestamp at time zone sp.timezone)
  and (m.disabled_at is null or m.disabled_at >= ((((a.metadata->>'local_date')::date+1)::timestamp) at time zone sp.timezone))
on conflict do nothing;
update public.achievements a set participants_recorded=true
where a.achievement_type='together_lit' and exists(select 1 from public.achievement_participants ap where ap.achievement_id=a.id);

with candidates as (
  select s.id space_id,t.days,t.tier,d.local_date end_date
  from public.spaces s
  cross join (values(1,'bronze'),(3,'silver'),(7,'gold')) t(days,tier)
  cross join lateral (
    select distinct (a.metadata->>'local_date')::date local_date
    from public.achievements a where a.space_id=s.id and a.achievement_type='together_lit'
  ) d
  where (select count(distinct (a2.metadata->>'local_date')::date)
    from public.achievements a2 where a2.space_id=s.id and a2.achievement_type='together_lit'
      and (a2.metadata->>'local_date')::date between d.local_date-t.days+1 and d.local_date)=t.days
), first_awards as (
  select distinct on(space_id,days) space_id,days,tier,end_date
  from candidates order by space_id,days,end_date
)
insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata,tier,participants_recorded)
select f.space_id,'together_streak','together-streak:'||f.days,
  ((f.end_date+1)::timestamp at time zone s.timezone),
  jsonb_build_object('days',f.days,'period_end_date',f.end_date),f.tier,true
from first_awards f join public.spaces s on s.id=f.space_id
on conflict(space_id,dedupe_key) do nothing;

insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot,participation_days)
select award.id,ap.member_id,max(ap.display_name_snapshot),count(distinct daily.id)::int
from public.achievements award
join public.achievements daily on daily.space_id=award.space_id and daily.achievement_type='together_lit'
  and (daily.metadata->>'local_date')::date between
    (award.metadata->>'period_end_date')::date-(award.metadata->>'days')::int+1
    and (award.metadata->>'period_end_date')::date
join public.achievement_participants ap on ap.achievement_id=daily.id
where award.achievement_type='together_streak'
group by award.id,ap.member_id on conflict do nothing;

revoke all on function private.validate_together_lit_achievement(),private.capture_achievement_participants(),private.award_goal_tiers() from public,anon,authenticated;
