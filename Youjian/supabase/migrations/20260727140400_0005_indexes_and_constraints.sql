create unique index one_owner_per_space on public.space_members(space_id) where role = 'owner';
create unique index active_display_name_per_space on public.space_members(space_id, lower(display_name)) where status = 'active';
create index space_members_user_status on public.space_members(user_id, status);
create index space_members_space_status on public.space_members(space_id, status);
create unique index one_active_focus_per_user on public.focus_sessions(user_id) where status in ('focusing', 'paused');
create unique index one_open_segment_per_session on public.focus_segments(session_id) where ended_at is null;
create unique index one_open_connection_interval_per_session on public.focus_connection_intervals(session_id) where ended_at is null;
create index focus_sessions_space_user_status_started on public.focus_sessions(space_id, user_id, status, started_at desc);
create index focus_segments_session_started on public.focus_segments(session_id, started_at);
create index focus_events_session_occurred on public.focus_events(session_id, occurred_at);
create index goal_proposals_space_status on public.goal_proposals(space_id, status);
create index goals_space_status_period on public.goals(space_id, status, starts_at, ends_at);

create function public.enforce_focus_history_immutability() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status in ('completed', 'discarded') then
    raise exception using errcode = '55000', message = 'settled focus sessions are immutable';
  end if;
  return new;
end $$;
create trigger settled_focus_sessions_are_immutable before update or delete on public.focus_sessions
for each row execute function public.enforce_focus_history_immutability();

create function public.enforce_segment_immutability() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' or old.ended_at is not null then
    raise exception using errcode = '55000', message = 'closed focus segments are immutable';
  end if;
  return new;
end $$;
create trigger closed_focus_segments_are_immutable before update or delete on public.focus_segments
for each row execute function public.enforce_segment_immutability();

create function public.enforce_append_only() returns trigger
language plpgsql set search_path = '' as $$ begin raise exception using errcode = '55000', message = 'append-only record'; end $$;
create trigger focus_events_are_append_only before update or delete on public.focus_events
for each row execute function public.enforce_append_only();

create function public.enforce_membership_consistency() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.space_members m where m.id = new.member_id and m.space_id = new.space_id and m.user_id = new.user_id) then
    raise exception using errcode = '23514', message = 'focus session membership does not match';
  end if;
  return new;
end $$;
create trigger focus_session_membership_consistency before insert or update of space_id,user_id,member_id on public.focus_sessions
for each row execute function public.enforce_membership_consistency();

create function public.enforce_space_owner_membership() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.space_members m where m.space_id = new.id and m.user_id = new.owner_id and m.role = 'owner' and m.status = 'active') then
    raise exception using errcode = '23514', message = 'space owner must be an active owner member';
  end if;
  return null;
end $$;
create constraint trigger space_owner_membership after insert or update of owner_id on public.spaces
deferrable initially deferred for each row execute function public.enforce_space_owner_membership();
