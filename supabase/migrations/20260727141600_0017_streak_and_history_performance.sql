create index focus_sessions_completed_history_user
on public.focus_sessions(space_id,user_id,completed_at desc,id desc)
where status in('completed','discarded');

create index focus_sessions_completed_history_space
on public.focus_sessions(space_id,completed_at desc,id desc)
where status in('completed','discarded');

create index focus_segments_closed_interval
on public.focus_segments(started_at,ended_at,session_id)
where ended_at is not null;

create or replace function public.current_streak_days(p_space_id uuid,p_user_id uuid,p_timezone text,p_at timestamptz default now()) returns integer
language sql stable security definer set search_path='' as $$
 with settings as (
   select (p_at at time zone p_timezone)::date as current_day,
          daily_checkin_target_minutes::bigint*60 as target
   from public.spaces where id=p_space_id
 ), daily as (
   select day_value::date as local_date,
          sum(floor(extract(epoch from(
            least(g.ended_at,(day_value::date+1)::timestamp at time zone p_timezone)-
            greatest(g.started_at,day_value::date::timestamp at time zone p_timezone)
          ))))::bigint as seconds
   from public.focus_sessions s
   join public.focus_segments g on g.session_id=s.id
   cross join lateral generate_series(
     ((g.started_at at time zone p_timezone)::date)::timestamp,
     (((g.ended_at-interval '1 microsecond') at time zone p_timezone)::date)::timestamp,
     interval '1 day'
   ) day_value
   where s.space_id=p_space_id and s.user_id=p_user_id and s.status='completed' and g.ended_at is not null
   group by day_value::date
 ), anchor as (
   select case when coalesce((select seconds from daily where local_date=settings.current_day),0)>=settings.target
               then settings.current_day else settings.current_day-1 end as local_date,
          settings.target
   from settings
 ), qualifying as (
   select daily.local_date,row_number() over(order by daily.local_date desc) as position
   from daily cross join anchor
   where daily.seconds>=anchor.target and daily.local_date<=anchor.local_date
 )
 select coalesce(count(*) filter(
   where qualifying.local_date=anchor.local_date-(qualifying.position::integer-1)
 ),0)::integer
 from anchor left join qualifying on true
$$;

revoke all on function public.current_streak_days(uuid,uuid,text,timestamptz) from public;
