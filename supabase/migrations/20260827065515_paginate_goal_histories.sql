create index goals_history_page
  on public.goals(space_id, ends_at desc, id desc)
  where status in ('completed', 'failed');

create index goal_proposals_history_page
  on public.goal_proposals(space_id, resolved_at desc, id desc)
  where status in ('rejected', 'expired');

create function private.decode_goal_history_cursor(
  p_cursor text,
  out cursor_time timestamptz,
  out cursor_id uuid
) returns record
language plpgsql stable security invoker set search_path='' as $$
declare
  parts text[];
begin
  parts := string_to_array(convert_from(decode(p_cursor, 'base64'), 'UTF8'), '|');
  if cardinality(parts) <> 2 then
    raise exception using errcode = '22023', message = 'invalid history cursor';
  end if;
  cursor_time := parts[1]::timestamptz;
  cursor_id := parts[2]::uuid;
end $$;

create function private.rpc_impl_list_goal_history(
  p_space_id uuid,
  p_limit integer,
  p_cursor text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  cursor_time timestamptz;
  cursor_id uuid;
  items jsonb;
  next_cursor text;
  snapshot_at timestamptz := now();
begin
  if not public.current_user_is_active_member(p_space_id) then
    return public.api_error('SPACE_ACCESS_DENIED');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 30 then
    return public.api_error('INVALID_LIMIT');
  end if;
  if p_cursor is not null then
    begin
      select decoded.cursor_time, decoded.cursor_id
        into cursor_time, cursor_id
        from private.decode_goal_history_cursor(p_cursor) decoded;
    exception when others then
      return public.api_error('INVALID_CURSOR');
    end;
  end if;

  with candidates as materialized (
    select g.id, g.ends_at
    from public.goals g
    where g.space_id = p_space_id
      and g.status in ('completed', 'failed')
      and (p_cursor is null or (g.ends_at, g.id) < (cursor_time, cursor_id))
    order by g.ends_at desc, g.id desc
    limit p_limit + 1
  ), chosen as (
    select id, ends_at
    from candidates
    order by ends_at desc, id desc
    limit p_limit
  )
  select
    coalesce(
      jsonb_agg(public.goal_json(id, snapshot_at) order by ends_at desc, id desc),
      '[]'::jsonb
    ),
    case when (select count(*) from candidates) > p_limit then (
      select encode(convert_to(ends_at::text || '|' || id::text, 'UTF8'), 'base64')
      from chosen
      order by ends_at, id
      limit 1
    ) end
  into items, next_cursor
  from chosen;

  return public.api_ok(jsonb_build_object(
    'space_id', p_space_id,
    'items', items,
    'next_cursor', next_cursor
  ));
end $$;

create function private.rpc_impl_list_goal_proposal_history(
  p_space_id uuid,
  p_limit integer,
  p_cursor text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  member_id uuid;
  cursor_time timestamptz;
  cursor_id uuid;
  items jsonb;
  next_cursor text;
begin
  if not public.current_user_is_active_member(p_space_id) then
    return public.api_error('SPACE_ACCESS_DENIED');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 30 then
    return public.api_error('INVALID_LIMIT');
  end if;
  if p_cursor is not null then
    begin
      select decoded.cursor_time, decoded.cursor_id
        into cursor_time, cursor_id
        from private.decode_goal_history_cursor(p_cursor) decoded;
    exception when others then
      return public.api_error('INVALID_CURSOR');
    end;
  end if;

  select sm.id into member_id
  from public.space_members sm
  where sm.space_id = p_space_id
    and sm.user_id = private.current_principal_id()
    and sm.status = 'active';

  with candidates as materialized (
    select gp.id, gp.resolved_at
    from public.goal_proposals gp
    where gp.space_id = p_space_id
      and gp.status in ('rejected', 'expired')
      and (p_cursor is null or (gp.resolved_at, gp.id) < (cursor_time, cursor_id))
    order by gp.resolved_at desc, gp.id desc
    limit p_limit + 1
  ), chosen as (
    select id, resolved_at
    from candidates
    order by resolved_at desc, id desc
    limit p_limit
  )
  select
    coalesce(
      jsonb_agg(public.proposal_json(id, member_id) order by resolved_at desc, id desc),
      '[]'::jsonb
    ),
    case when (select count(*) from candidates) > p_limit then (
      select encode(convert_to(resolved_at::text || '|' || id::text, 'UTF8'), 'base64')
      from chosen
      order by resolved_at, id
      limit 1
    ) end
  into items, next_cursor
  from chosen;

  return public.api_ok(jsonb_build_object(
    'space_id', p_space_id,
    'items', items,
    'next_cursor', next_cursor
  ));
end $$;

create function public.list_goal_history(
  p_space_id uuid,
  p_limit integer default 3,
  p_cursor text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  return private.rpc_impl_list_goal_history(p_space_id, p_limit, p_cursor);
exception when others then
  return private.rpc_internal_error_envelope('list_goal_history', sqlstate);
end $$;

create function public.list_goal_proposal_history(
  p_space_id uuid,
  p_limit integer default 4,
  p_cursor text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  return private.rpc_impl_list_goal_proposal_history(p_space_id, p_limit, p_cursor);
exception when others then
  return private.rpc_internal_error_envelope('list_goal_proposal_history', sqlstate);
end $$;

create or replace function private.rpc_impl_get_goals_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  member_id uuid;
  active jsonb;
  scheduled jsonb;
  pending jsonb;
  history jsonb;
  proposal_history jsonb;
  snapshot_at timestamptz := now();
begin
  if not public.current_user_is_active_member(p_space_id) then
    return public.api_error('SPACE_ACCESS_DENIED');
  end if;
  select id into member_id
  from public.space_members
  where space_id = p_space_id
    and user_id = private.current_principal_id()
    and status = 'active';
  perform private.run_space_goal_maintenance(p_space_id, snapshot_at);
  select coalesce(jsonb_agg(public.goal_json(id, snapshot_at) order by starts_at), '[]'::jsonb)
    into active from public.goals where space_id = p_space_id and status = 'active';
  select coalesce(jsonb_agg(public.goal_json(id, snapshot_at) order by starts_at), '[]'::jsonb)
    into scheduled from public.goals where space_id = p_space_id and status = 'scheduled';
  select coalesce(jsonb_agg(public.proposal_json(id, member_id) order by created_at desc), '[]'::jsonb)
    into pending from public.goal_proposals where space_id = p_space_id and status = 'pending';
  select coalesce(jsonb_agg(public.goal_json(id, snapshot_at) order by ends_at desc, id desc), '[]'::jsonb)
    into history
    from (
      select id, ends_at
      from public.goals
      where space_id = p_space_id and status in ('completed', 'failed')
      order by ends_at desc, id desc
      limit 3
    ) recent_goals;
  select coalesce(jsonb_agg(public.proposal_json(id, member_id) order by resolved_at desc, id desc), '[]'::jsonb)
    into proposal_history
    from (
      select id, resolved_at
      from public.goal_proposals
      where space_id = p_space_id and status in ('rejected', 'expired')
      order by resolved_at desc, id desc
      limit 4
    ) recent_proposals;
  return public.api_ok(jsonb_build_object(
    'space_id', p_space_id,
    'active_goals', active,
    'scheduled_goals', scheduled,
    'pending_proposals', pending,
    'history', history,
    'proposal_history', proposal_history
  ));
end $$;

revoke all on function private.decode_goal_history_cursor(text),
  private.rpc_impl_list_goal_history(uuid, integer, text),
  private.rpc_impl_list_goal_proposal_history(uuid, integer, text)
  from public, anon, authenticated;
revoke all on function public.list_goal_history(uuid, integer, text),
  public.list_goal_proposal_history(uuid, integer, text)
  from public, anon;
grant execute on function public.list_goal_history(uuid, integer, text),
  public.list_goal_proposal_history(uuid, integer, text)
  to authenticated;
