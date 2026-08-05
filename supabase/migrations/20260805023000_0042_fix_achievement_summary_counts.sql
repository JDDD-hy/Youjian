-- Count logical achievement events, not compatibility aliases, in summary cards.

create or replace function private.rpc_impl_list_achievements(p_space_id uuid,p_limit integer,p_cursor text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m uuid; items jsonb;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  if p_cursor is not null then return public.api_error('INVALID_CURSOR'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  with raw as(
    select ac.*,case
      when achievement_type in('together_streak','three_days_together') then 'together_streak'
      when achievement_type in('goal_milestone','first_goal') then 'goal_milestone'
      when achievement_type='focus_milestone' then 'focus_milestone'
      when achievement_type='fellow_travelers' then 'fellow_travelers'
      else achievement_type end card_type,
      case tier when 'diamond' then 4 when 'gold' then 3 when 'silver' then 2 else 1 end tier_rank,
      row_number() over(partition by achievement_type order by earned_at,id) legacy_rank
    from public.achievements ac where space_id=p_space_id
      and achievement_type<>'together_lit'
  ), base as(
    select r.* from raw r
    where (r.achievement_type<>'three_days_together' or (r.legacy_rank=1 and not exists(
      select 1 from raw canonical where canonical.achievement_type='together_streak'
        and coalesce((canonical.metadata->>'days')::int,0)=3
    ))) and (r.achievement_type<>'first_goal' or (r.legacy_rank=1 and not exists(
      select 1 from raw canonical where canonical.achievement_type='goal_milestone'
        and coalesce((canonical.metadata->>'completed_goal_count')::int,0)=1
    )))
  ), ranked as(
    select b.*,row_number() over(partition by card_type order by tier_rank desc,earned_at desc,id desc) pick,
      count(*) over(partition by card_type) event_count,
      min(earned_at) over(partition by card_type) first_at,
      max(earned_at) over(partition by card_type) last_at
    from base b
  ),cards as(select * from ranked where pick=1 order by last_at desc limit p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',case when card_type in('together_streak','goal_milestone','focus_milestone','fellow_travelers','chance_encounter','focus_relay','living_flame') then card_type else id::text end,
    'achievement_type',card_type,'tier',tier,'earned_at',last_at,
    'first_earned_at',first_at,'last_earned_at',last_at,'count',event_count,'metadata',metadata,
    'participants_recorded',true,'seen',not exists(select 1 from base unread where unread.card_type=cards.card_type
      and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=unread.id and ar.member_id=m)),
    'participants',(select coalesce(jsonb_agg(jsonb_build_object('member_id',ap.member_id,
      'display_name',ap.display_name_snapshot,'participation_days',ap.participation_days) order by ap.display_name_snapshot),'[]'::jsonb)
      from public.achievement_participants ap where ap.achievement_id=cards.id),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('achievement_id',ev.id,'earned_at',ev.earned_at,
      'metadata',ev.metadata,'participants',(select coalesce(jsonb_agg(jsonb_build_object('member_id',ep.member_id,
        'display_name',ep.display_name_snapshot,'participation_days',ep.participation_days) order by ep.display_name_snapshot),'[]'::jsonb)
        from public.achievement_participants ep where ep.achievement_id=ev.id)) order by ev.earned_at desc),'[]'::jsonb)
      from base ev where ev.card_type=cards.card_type)
  ) order by last_at desc),'[]'::jsonb) into items from cards;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',null));
end $$;

revoke all on function private.rpc_impl_list_achievements(uuid,integer,text) from public,anon,authenticated;
