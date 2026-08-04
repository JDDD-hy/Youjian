-- Aggregate repeatable achievement events into one card per series/type.

create or replace function private.rpc_impl_list_personal_achievements(
  p_space_id uuid,p_limit integer,p_cursor text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); cursor_time timestamptz; cursor_type text; items jsonb; next_cursor text; v_seen_at timestamptz;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  select max(n.personal_seen_at) into v_seen_at from public.achievement_nav_reads n
    join public.space_members m on m.id=n.member_id where m.user_id=a;
  if p_cursor is not null then begin
    cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz;
    cursor_type:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2);
  exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
  with rows as(
    select pa.*,row_number() over(order by last_earned_at desc,achievement_type desc) rn
    from public.personal_achievements pa where user_id=a
      and(p_cursor is null or(last_earned_at,achievement_type)<(cursor_time,cursor_type))
    order by last_earned_at desc,achievement_type desc limit p_limit+1
  ),chosen as(select * from rows where rn<=p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',achievement_type,'achievement_type',achievement_type,'tier',tier,
    'earned_at',last_earned_at,'first_earned_at',first_earned_at,'last_earned_at',last_earned_at,
    'count',count,'metadata',metadata,'seen',coalesce(v_seen_at,'-infinity')>=last_earned_at,
    'events',(select coalesce(jsonb_agg(jsonb_build_object('earned_at',e.earned_at,'local_date',e.local_date,
      'source_space_id',e.source_space_id,'metadata',e.metadata) order by e.earned_at desc),'[]'::jsonb)
      from public.personal_achievement_awards e where e.user_id=a and e.achievement_type=chosen.achievement_type)
  ) order by last_earned_at desc,achievement_type desc),'[]'::jsonb),
  case when(select count(*) from rows)>p_limit then(select encode(convert_to(last_earned_at::text||'|'||achievement_type,'UTF8'),'base64') from chosen order by last_earned_at,achievement_type limit 1) end
  into items,next_cursor from chosen;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',next_cursor));
end $$;

create or replace function private.rpc_impl_list_achievements(p_space_id uuid,p_limit integer,p_cursor text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m uuid; items jsonb;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  if p_cursor is not null then return public.api_error('INVALID_CURSOR'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  with base as(
    select ac.*,case
      when achievement_type in('together_streak','three_days_together') then 'together_streak'
      when achievement_type in('goal_milestone','first_goal') then 'goal_milestone'
      when achievement_type='focus_milestone' then 'focus_milestone'
      when achievement_type='fellow_travelers' then 'fellow_travelers'
      else achievement_type end card_type,
      case tier when 'diamond' then 4 when 'gold' then 3 when 'silver' then 2 else 1 end tier_rank
    from public.achievements ac where space_id=p_space_id
      and achievement_type not in('together_lit')
  ), ranked as(
    select b.*,row_number() over(partition by card_type order by tier_rank desc,earned_at desc,id desc) pick,
      count(*) over(partition by card_type) event_count,
      min(earned_at) over(partition by card_type) first_at,
      max(earned_at) over(partition by card_type) last_at
    from base b
  ),cards as(select * from ranked where pick=1 order by last_at desc limit p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',card_type,'achievement_type',card_type,'tier',tier,'earned_at',last_at,
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

revoke all on function private.rpc_impl_list_personal_achievements(uuid,integer,text),
  private.rpc_impl_list_achievements(uuid,integer,text) from public,anon,authenticated;

-- Preserve the home-page achievement toast for global personal achievements.
alter function private.rpc_impl_get_home_snapshot(uuid)
  rename to legacy_get_home_snapshot_before_personal_achievements;
create function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; a uuid:=auth.uid(); v_seen_at timestamptz; personal jsonb;
begin
  result:=private.legacy_get_home_snapshot_before_personal_achievements(p_space_id);
  if result->>'ok'<>'true' then return result; end if;
  select max(n.personal_seen_at) into v_seen_at from public.achievement_nav_reads n
    join public.space_members m on m.id=n.member_id where m.user_id=a;
  select jsonb_build_object(
    'achievement_id',pa.achievement_type,'achievement_type',pa.achievement_type,
    'tier',pa.tier,'earned_at',pa.last_earned_at,'first_earned_at',pa.first_earned_at,
    'last_earned_at',pa.last_earned_at,'count',pa.count,'metadata',pa.metadata,'seen',false
  ) into personal from public.personal_achievements pa
  where pa.user_id=a and pa.last_earned_at>coalesce(v_seen_at,'-infinity')
  order by pa.last_earned_at limit 1;
  return jsonb_set(result,'{data,unseen_personal_achievement}',coalesce(personal,'null'::jsonb),true);
end $$;
revoke all on function private.legacy_get_home_snapshot_before_personal_achievements(uuid),
  private.rpc_impl_get_home_snapshot(uuid) from public,anon,authenticated;
