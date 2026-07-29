create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  timezone text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 30 and name = btrim(name)),
  owner_id uuid not null references auth.users(id),
  timezone text not null,
  member_limit smallint not null default 3 check (member_limit between 2 and 12),
  daily_checkin_target_minutes smallint not null default 60 check (daily_checkin_target_minutes between 5 and 720),
  invite_token_hash text not null unique,
  invite_version integer not null default 1 check (invite_version > 0),
  created_at timestamptz not null default now()
);

create table public.space_members (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 20 and display_name = btrim(display_name)),
  role public.member_role not null,
  status public.member_status not null default 'active',
  joined_at timestamptz not null default now(),
  disabled_at timestamptz,
  disabled_by uuid references auth.users(id),
  unique (space_id, user_id),
  check ((status = 'active' and disabled_at is null and disabled_by is null) or
         (status = 'disabled' and disabled_at is not null and disabled_by is not null)),
  check (not (role = 'owner' and status = 'disabled'))
);
