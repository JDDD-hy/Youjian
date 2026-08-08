-- Add chart-ready, privacy-scoped distribution details to the existing stats
-- envelope. Only completed sessions and closed segments are credited.

create or replace function private.rpc_impl_get_stats_summary(
  p_space_id uuid,p_view text,p_period text,p_anchor_local_date date
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  output jsonb;
  a uuid:=auth.uid();
  rewritten_days jsonb;
  checkins int;
  tz text;
  utc_start timestamptz;
  utc_end timestamptz;
  snapshot_at timestamptz:=now();
  members jsonb;
  hourly_buckets jsonb:='[]'::jsonb;
begin
  output:=private.legacy_get_stats_summary_without_space_context(p_space_id,p_view,p_period,p_anchor_local_date);
  if output->>'ok'<>'true' then return output; end if;

  tz:=output#>>'{data,timezone}';
  utc_start:=(output#>>'{data,period_start}')::timestamptz;
  utc_end:=(output#>>'{data,period_end}')::timestamptz;

  if p_view='mine' then
    select coalesce(jsonb_agg(jsonb_set(day_value,'{checkin_completed}',to_jsonb(
        (day_value->>'credited_focus_seconds')::integer >= public.personal_goal_minutes(p_space_id,a,(day_value->>'local_date')::date)*60
      ),true) order by day_value->>'local_date'),'[]'::jsonb),
      count(*) filter(where (day_value->>'credited_focus_seconds')::integer >= public.personal_goal_minutes(p_space_id,a,(day_value->>'local_date')::date)*60)::integer
    into rewritten_days,checkins from jsonb_array_elements(output#>'{data,days}') day_value;
    output:=jsonb_set(output,'{data,days}',rewritten_days,true);
    output:=jsonb_set(output,'{data,checkin_day_count}',to_jsonb(checkins),true);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name) order by
    m.joined_at,m.id),'[]'::jsonb)
  into members
  from public.space_members m
  where m.space_id=p_space_id and (p_view='space' or m.user_id=a)
    and (m.status='active' or exists(
      select 1 from public.focus_sessions s where s.member_id=m.id and s.status='completed'
        and s.completed_at>=utc_start and s.started_at<utc_end
    ));

  with source_days as(
    select value day_value,(value->>'local_date')::date local_date
    from jsonb_array_elements(output#>'{data,days}')
  ), enriched as(
    select d.local_date,jsonb_set(d.day_value,'{member_contributions}',coalesce((
      select jsonb_agg(jsonb_build_object(
        'member_id',contrib.member_id,
        'display_name',contrib.display_name,
        'credited_focus_seconds',contrib.seconds
      ) order by contrib.joined_at,contrib.member_id)
      from (
        select m.id member_id,m.display_name,m.joined_at,
          floor(sum(extract(epoch from(
            least(seg.ended_at,(d.local_date+1)::timestamp at time zone tz,utc_end,snapshot_at)-
            greatest(seg.started_at,d.local_date::timestamp at time zone tz,utc_start)
          ))))::integer seconds
        from public.focus_sessions s
        join public.focus_segments seg on seg.session_id=s.id
        join public.space_members m on m.id=s.member_id
        where s.space_id=p_space_id and s.status='completed' and seg.ended_at is not null
          and (p_view='space' or s.user_id=a)
          and seg.started_at<least((d.local_date+1)::timestamp at time zone tz,utc_end,snapshot_at)
          and seg.ended_at>greatest(d.local_date::timestamp at time zone tz,utc_start)
        group by m.id,m.display_name,m.joined_at
      ) contrib where contrib.seconds>0
    ),'[]'::jsonb),true) day_value
    from source_days d
    where p_period<>'monthly' or d.local_date<=(snapshot_at at time zone tz)::date
  )
  select coalesce(jsonb_agg(day_value order by local_date),'[]'::jsonb) into rewritten_days from enriched;

  if p_period='daily' then
    if p_anchor_local_date<=(snapshot_at at time zone tz)::date then
      with hours as(
      select h hour_index,
        p_anchor_local_date::timestamp+make_interval(hours=>h) local_lo,
        p_anchor_local_date::timestamp+make_interval(hours=>h+1) local_hi
      from generate_series(0,case
        when p_anchor_local_date<(snapshot_at at time zone tz)::date then 23
        else least(23,extract(hour from snapshot_at at time zone tz)::integer)
      end) h
      )
      select coalesce(jsonb_agg(jsonb_build_object(
        'hour',h.hour_index,
        'credited_focus_seconds',coalesce((
          select floor(sum(extract(epoch from(
            least(seg.ended_at,h.local_hi at time zone tz,snapshot_at)-
            greatest(seg.started_at,h.local_lo at time zone tz)
          ))))::integer
          from public.focus_sessions s join public.focus_segments seg on seg.session_id=s.id
          where s.space_id=p_space_id and s.status='completed' and seg.ended_at is not null
            and (p_view='space' or s.user_id=a)
            and seg.started_at<least(h.local_hi at time zone tz,snapshot_at)
            and seg.ended_at>h.local_lo at time zone tz
        ),0)
      ) order by h.hour_index),'[]'::jsonb) into hourly_buckets from hours h;
    end if;
  end if;

  output:=jsonb_set(output,'{data,space_id}',to_jsonb(p_space_id),true);
  output:=jsonb_set(output,'{data,anchor_local_date}',to_jsonb(p_anchor_local_date),true);
  output:=jsonb_set(output,'{data,members}',members,true);
  output:=jsonb_set(output,'{data,days}',rewritten_days,true);
  output:=jsonb_set(output,'{data,hourly_buckets}',hourly_buckets,true);
  return output;
end $$;

revoke all on function private.rpc_impl_get_stats_summary(uuid,text,text,date) from public,anon,authenticated;
