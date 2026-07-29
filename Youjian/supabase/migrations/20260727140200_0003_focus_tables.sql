create table public.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  member_id uuid not null references public.space_members(id) on delete restrict,
  task_name text not null check (char_length(btrim(task_name)) between 1 and 80 and task_name = btrim(task_name)),
  category public.focus_category,
  status public.focus_status not null,
  accumulated_focus_seconds integer not null default 0 check (accumulated_focus_seconds >= 0 and accumulated_focus_seconds <= 21600),
  active_segment_started_at timestamptz,
  paused_at timestamptz,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  completion_reason public.completion_reason,
  last_seen_at timestamptz not null default now(),
  unconfirmed_connection_seconds integer not null default 0 check (unconfirmed_connection_seconds >= 0),
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  check (
    (status = 'focusing' and active_segment_started_at is not null and paused_at is null and completed_at is null and completion_reason is null) or
    (status = 'paused' and active_segment_started_at is null and paused_at is not null and completed_at is null and completion_reason is null) or
    (status in ('completed', 'discarded') and active_segment_started_at is null and paused_at is null and completed_at is not null and completion_reason is not null)
  )
);
create table public.focus_segments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.focus_sessions(id) on delete restrict,
  started_at timestamptz not null,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  check (ended_at is null or ended_at > started_at)
);

create table public.focus_events (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.focus_sessions(id) on delete restrict,
  actor_id uuid references auth.users(id),
  event_type public.focus_event_type not null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object')
);

create table public.focus_connection_intervals (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.focus_sessions(id) on delete restrict,
  started_at timestamptz not null,
  ended_at timestamptz,
  detected_from_last_seen_at timestamptz not null,
  check (ended_at is null or ended_at > started_at)
);

create table public.focus_commands (
  actor_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key uuid not null,
  command_type text not null,
  request_hash text not null,
  session_id uuid references public.focus_sessions(id) on delete restrict,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, idempotency_key)
);
