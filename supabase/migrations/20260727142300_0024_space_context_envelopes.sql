alter function private.rpc_impl_get_stats_summary(uuid,text,text,date) rename to legacy_get_stats_summary_without_space_context;
alter function private.rpc_impl_get_goals_snapshot(uuid) rename to legacy_get_goals_snapshot_without_space_context;
alter function private.rpc_impl_list_focus_history(uuid,text,timestamptz,timestamptz,integer,text) rename to legacy_list_focus_history_without_space_context;
alter function private.rpc_impl_list_achievements(uuid,integer,text) rename to legacy_list_achievements_without_space_context;

revoke all on function
 private.legacy_get_stats_summary_without_space_context(uuid,text,text,date),
 private.legacy_get_goals_snapshot_without_space_context(uuid),
 private.legacy_list_focus_history_without_space_context(uuid,text,timestamptz,timestamptz,integer,text),
 private.legacy_list_achievements_without_space_context(uuid,integer,text)
from public,anon,authenticated;

create function private.rpc_impl_get_stats_summary(p_space_id uuid,p_view text,p_period text,p_anchor_local_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare output jsonb;
begin
 output:=private.legacy_get_stats_summary_without_space_context(p_space_id,p_view,p_period,p_anchor_local_date);
 if output->>'ok'='true' then output:=jsonb_set(output,'{data,space_id}',to_jsonb(p_space_id),true); end if;
 return output;
end $$;

create function private.rpc_impl_get_goals_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare output jsonb;
begin
 output:=private.legacy_get_goals_snapshot_without_space_context(p_space_id);
 if output->>'ok'='true' then output:=jsonb_set(output,'{data,space_id}',to_jsonb(p_space_id),true); end if;
 return output;
end $$;

create function private.rpc_impl_list_focus_history(p_space_id uuid,p_view text,p_period_start timestamptz,p_period_end timestamptz,p_limit integer,p_cursor text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare output jsonb;
begin
 output:=private.legacy_list_focus_history_without_space_context(p_space_id,p_view,p_period_start,p_period_end,p_limit,p_cursor);
 if output->>'ok'='true' then output:=jsonb_set(output,'{data,space_id}',to_jsonb(p_space_id),true); end if;
 return output;
end $$;

create function private.rpc_impl_list_achievements(p_space_id uuid,p_limit integer,p_cursor text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare output jsonb;
begin
 output:=private.legacy_list_achievements_without_space_context(p_space_id,p_limit,p_cursor);
 if output->>'ok'='true' then output:=jsonb_set(output,'{data,space_id}',to_jsonb(p_space_id),true); end if;
 return output;
end $$;

revoke all on function
 private.rpc_impl_get_stats_summary(uuid,text,text,date),
 private.rpc_impl_get_goals_snapshot(uuid),
 private.rpc_impl_list_focus_history(uuid,text,timestamptz,timestamptz,integer,text),
 private.rpc_impl_list_achievements(uuid,integer,text)
from public,anon,authenticated;
