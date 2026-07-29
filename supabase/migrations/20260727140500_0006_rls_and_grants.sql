create function public.current_user_is_active_member(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.space_members m where m.space_id = p_space_id and m.user_id = auth.uid() and m.status = 'active')
$$;
create function public.current_user_is_owner(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.space_members m where m.space_id = p_space_id and m.user_id = auth.uid() and m.role = 'owner' and m.status = 'active')
$$;
create function public.validate_iana_timezone(p_timezone text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from pg_catalog.pg_timezone_names where name = p_timezone)
$$;
create function public.normalize_display_name(p_name text) returns text
language sql immutable set search_path = '' as $$ select lower(btrim(p_name)) $$;

revoke all on function public.current_user_is_active_member(uuid) from public;
revoke all on function public.current_user_is_owner(uuid) from public;
revoke all on function public.validate_iana_timezone(text) from public;
grant execute on function public.current_user_is_active_member(uuid), public.current_user_is_owner(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.focus_sessions enable row level security;
alter table public.focus_segments enable row level security;
alter table public.focus_events enable row level security;
alter table public.focus_connection_intervals enable row level security;
alter table public.focus_commands enable row level security;
alter table public.goal_proposals enable row level security;
alter table public.goal_proposal_members enable row level security;
alter table public.goals enable row level security;
alter table public.goal_participants enable row level security;
alter table public.achievements enable row level security;
alter table public.achievement_reads enable row level security;

create policy profiles_select_self on public.profiles for select to authenticated using (id = auth.uid());
create policy spaces_select_members on public.spaces for select to authenticated using (public.current_user_is_active_member(id));
create policy members_select_space on public.space_members for select to authenticated using (public.current_user_is_active_member(space_id));
create policy sessions_select_space on public.focus_sessions for select to authenticated using (public.current_user_is_active_member(space_id));
create policy segments_select_space on public.focus_segments for select to authenticated using (
  exists(select 1 from public.focus_sessions s where s.id = session_id and public.current_user_is_active_member(s.space_id))
);
create policy events_select_space on public.focus_events for select to authenticated using (
  exists(select 1 from public.focus_sessions s where s.id = session_id and public.current_user_is_active_member(s.space_id))
);
create policy proposals_select_space on public.goal_proposals for select to authenticated using (public.current_user_is_active_member(space_id));
create policy proposal_members_select_space on public.goal_proposal_members for select to authenticated using (
  exists(select 1 from public.goal_proposals p where p.id = proposal_id and public.current_user_is_active_member(p.space_id))
);
create policy goals_select_space on public.goals for select to authenticated using (public.current_user_is_active_member(space_id));
create policy goal_participants_select_space on public.goal_participants for select to authenticated using (
  exists(select 1 from public.goals g where g.id = goal_id and public.current_user_is_active_member(g.space_id))
);
create policy achievements_select_space on public.achievements for select to authenticated using (public.current_user_is_active_member(space_id));

revoke all on all tables in schema public from anon, authenticated;
grant select on public.profiles, public.spaces, public.space_members, public.focus_sessions, public.focus_segments,
  public.focus_events, public.goal_proposals, public.goal_proposal_members, public.goals, public.goal_participants,
  public.achievements, public.achievement_reads to authenticated;
grant usage on schema public to anon, authenticated;
