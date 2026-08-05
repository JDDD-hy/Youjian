-- Historical goal progress is immutable after the goal is settled.

create or replace function public.goal_progress_json(p_goal_id uuid,p_at timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g public.goals%rowtype; tz text; seconds int; members jsonb; done boolean; shared_days int; target_seconds int; progress_at timestamptz;
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
  with vals as(
   select m.id,m.display_name,coalesce(floor(sum(extract(epoch from(least(fs.ended_at,progress_at)-greatest(fs.started_at,g.starts_at)))) filter(where s.status='completed')),0)::int sec
   from public.goal_participants gp join public.space_members m on m.id=gp.member_id left join public.focus_sessions s on s.member_id=m.id
   left join public.focus_segments fs on fs.session_id=s.id and fs.ended_at>g.starts_at and fs.started_at<progress_at
   where gp.goal_id=g.id group by m.id,m.display_name
  ) select coalesce(jsonb_agg(jsonb_build_object('member_id',id,'display_name',display_name,'credited_value',sec/60,'completed',sec>=g.target_value*60) order by display_name),'[]'),bool_and(sec>=g.target_value*60) into members,done from vals;
  return jsonb_build_object('credited_value',null,'completed',coalesce(done,false),'members',members);
 else
  with local_days as(select d::date local_date from generate_series((g.starts_at at time zone tz)::date,((progress_at-interval '1 microsecond') at time zone tz)::date,interval '1 day') d),
  qualifying as(select d.local_date from local_days d where not exists(select 1 from public.goal_participants gp join public.space_members m on m.id=gp.member_id where gp.goal_id=g.id and public.credited_seconds_for_day(g.space_id,m.user_id,d.local_date,tz)<target_seconds))
  select count(*)::int into shared_days from qualifying;
  return jsonb_build_object('credited_value',shared_days,'completed',shared_days>=g.target_value,'members',null);
 end if;
end $$;

revoke all on function public.goal_progress_json(uuid,timestamptz) from public;
