create or replace function private.rpc_impl_get_goals_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare member_id uuid; active jsonb; scheduled jsonb; pending jsonb; history jsonb; proposal_history jsonb; snapshot_at timestamptz:=now();
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select id into member_id from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active';
 perform private.run_space_goal_maintenance(p_space_id,snapshot_at);
 select coalesce(jsonb_agg(public.goal_json(id,snapshot_at) order by starts_at),'[]') into active from public.goals where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(public.goal_json(id,snapshot_at) order by starts_at),'[]') into scheduled from public.goals where space_id=p_space_id and status='scheduled';
 select coalesce(jsonb_agg(public.proposal_json(id,member_id) order by created_at desc),'[]') into pending from public.goal_proposals where space_id=p_space_id and status='pending';
 select coalesce(jsonb_agg(public.goal_json(id,snapshot_at) order by ends_at desc),'[]') into history from public.goals where space_id=p_space_id and status in('completed','failed');
 select coalesce(jsonb_agg(public.proposal_json(id,member_id) order by resolved_at desc,id),'[]') into proposal_history from public.goal_proposals where space_id=p_space_id and status in('rejected','expired');
 return public.api_ok(jsonb_build_object('space_id',p_space_id,'active_goals',active,'scheduled_goals',scheduled,'pending_proposals',pending,'history',history,'proposal_history',proposal_history));
end $$;
revoke all on function private.rpc_impl_get_goals_snapshot(uuid) from public,anon,authenticated;
