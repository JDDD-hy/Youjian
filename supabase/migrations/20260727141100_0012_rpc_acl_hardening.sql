do $acl$
declare r record;
begin
 for r in select p.oid::regprocedure::text signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 loop execute format('revoke all on function %s from public',r.signature); end loop;
end $acl$;

grant execute on function public.current_user_is_active_member(uuid),public.current_user_is_owner(uuid) to authenticated;
grant execute on function public.get_invite_preview(text) to anon,authenticated;
grant execute on function public.get_my_membership(),public.create_space(text,text,text,text,smallint,uuid),public.join_space(text,text,text,uuid),
 public.rotate_invite(uuid,uuid),public.start_focus(uuid,text,text,uuid),public.pause_focus(uuid,uuid),public.resume_focus(uuid,uuid),
 public.end_focus(uuid,uuid),public.heartbeat_focus(uuid),public.get_home_snapshot(uuid),public.get_stats_summary(uuid,text,text,date),
 public.list_focus_history(uuid,text,timestamptz,timestamptz,integer,text),public.get_focus_session_detail(uuid),
 public.get_goals_snapshot(uuid),public.propose_goal(uuid,text,text,integer,uuid),public.vote_goal_proposal(uuid,text,uuid),
 public.list_achievements(uuid,integer,text),public.mark_achievement_seen(uuid,uuid),public.get_space_settings(uuid),public.disable_member(uuid,uuid,uuid)
 to authenticated;
