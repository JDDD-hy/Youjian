create table public.goal_proposals (
  id uuid primary key default gen_random_uuid(), space_id uuid not null references public.spaces(id),
  proposer_member_id uuid not null references public.space_members(id), goal_type public.goal_type not null,
  period_type public.period_type not null, target_value integer not null check (target_value > 0),
  status public.proposal_status not null default 'pending', expires_at timestamptz not null,
  effective_period_start timestamptz not null, created_at timestamptz not null default now(), resolved_at timestamptz,
  check ((status = 'pending' and resolved_at is null) or (status <> 'pending' and resolved_at is not null))
);
create table public.goal_proposal_members (
  proposal_id uuid not null references public.goal_proposals(id), member_id uuid not null references public.space_members(id),
  vote public.goal_vote, voted_at timestamptz, primary key (proposal_id, member_id),
  check ((vote is null and voted_at is null) or (vote is not null and voted_at is not null))
);
create table public.goals (
  id uuid primary key default gen_random_uuid(), source_proposal_id uuid unique not null references public.goal_proposals(id),
  space_id uuid not null references public.spaces(id), goal_type public.goal_type not null, period_type public.period_type not null,
  target_value integer not null check (target_value > 0), starts_at timestamptz not null, ends_at timestamptz not null,
  status public.goal_status not null default 'scheduled', completed_at timestamptz, created_at timestamptz not null default now(),
  check (ends_at > starts_at), check ((status in ('completed','failed')) = (completed_at is not null))
);
create table public.goal_participants (
  goal_id uuid not null references public.goals(id), member_id uuid not null references public.space_members(id), primary key (goal_id, member_id)
);
create table public.achievements (
  id uuid primary key default gen_random_uuid(), space_id uuid not null references public.spaces(id),
  achievement_type text not null, dedupe_key text not null, earned_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb, unique (space_id, dedupe_key)
);
create table public.achievement_reads (
  achievement_id uuid not null references public.achievements(id), member_id uuid not null references public.space_members(id),
  seen_at timestamptz not null default now(), primary key (achievement_id, member_id)
);
