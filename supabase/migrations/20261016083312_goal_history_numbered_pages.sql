-- Resolve a numbered page to the existing keyset cursor; hydrate only that page.
create function private.rpc_impl_list_goal_history_page(
  p_space_id uuid, p_kind text, p_page integer, p_limit integer
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  total bigint;
  page_count bigint;
  selected_page integer;
  boundary_time timestamptz;
  boundary_id uuid;
  page_cursor text;
  result jsonb;
begin
  if not public.current_user_is_active_member(p_space_id) then
    return public.api_error('SPACE_ACCESS_DENIED');
  end if;
  if p_kind is null or p_kind not in ('goals', 'proposals') then
    return public.api_error('INVALID_HISTORY_KIND');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 30 then
    return public.api_error('INVALID_LIMIT');
  end if;
  if p_page is null or p_page < 1 then
    return public.api_error('INVALID_PAGE');
  end if;
  if p_kind = 'goals' then
    select count(*) into total from public.goals
    where space_id = p_space_id and status in ('completed', 'failed');
  else
    select count(*) into total from public.goal_proposals
    where space_id = p_space_id and status in ('rejected', 'expired');
  end if;
  page_count := greatest(1, (total + p_limit - 1) / p_limit);
  -- History can shrink while a panel is open; return the last remaining page.
  selected_page := least(p_page, page_count)::integer;
  if selected_page > 1 then
    if p_kind = 'goals' then
      select ends_at, id into boundary_time, boundary_id from public.goals
      where space_id = p_space_id and status in ('completed', 'failed')
      order by ends_at desc, id desc
      offset ((selected_page::bigint - 1) * p_limit - 1) limit 1;
    else
      select resolved_at, id into boundary_time, boundary_id from public.goal_proposals
      where space_id = p_space_id and status in ('rejected', 'expired')
      order by resolved_at desc, id desc
      offset ((selected_page::bigint - 1) * p_limit - 1) limit 1;
    end if;
    page_cursor := encode(convert_to(boundary_time::text || '|' || boundary_id::text, 'UTF8'), 'base64');
  end if;
  if p_kind = 'goals' then
    result := private.rpc_impl_list_goal_history(p_space_id, p_limit, page_cursor);
  else
    result := private.rpc_impl_list_goal_proposal_history(p_space_id, p_limit, page_cursor);
  end if;
  if result->>'ok' <> 'true' then return result; end if;
  return jsonb_set(result, '{data}', (result->'data') || jsonb_build_object(
    'total_count', total, 'page', selected_page, 'page_count', page_count
  ));
end $$;

create function public.list_goal_history_page(
  p_space_id uuid, p_kind text, p_page integer default 1, p_limit integer default 4
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  return private.rpc_impl_list_goal_history_page(p_space_id, p_kind, p_page, p_limit);
exception when others then
  return private.rpc_internal_error_envelope('list_goal_history_page', sqlstate);
end $$;

revoke all on function private.rpc_impl_list_goal_history_page(uuid,text,integer,integer) from public, anon, authenticated;
revoke all on function public.list_goal_history_page(uuid,text,integer,integer) from public, anon;
grant execute on function public.list_goal_history_page(uuid,text,integer,integer) to authenticated;
