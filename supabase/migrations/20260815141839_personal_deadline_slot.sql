create table public.personal_deadlines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  title varchar(40) not null,
  target_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint personal_deadlines_title_valid
    check (title=btrim(title) and char_length(title) between 1 and 40)
);

alter table public.personal_deadlines enable row level security;

create policy personal_deadlines_select_own
on public.personal_deadlines for select to authenticated
using (user_id=(select private.current_principal_id()));

create policy personal_deadlines_insert_own
on public.personal_deadlines for insert to authenticated
with check (user_id=(select private.current_principal_id()));

create policy personal_deadlines_update_own
on public.personal_deadlines for update to authenticated
using (user_id=(select private.current_principal_id()))
with check (user_id=(select private.current_principal_id()));

revoke all on table public.personal_deadlines from public,anon,authenticated;

create function private.personal_deadline_json(p_deadline public.personal_deadlines)
returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'id',p_deadline.id,
    'title',p_deadline.title,
    'target_date',p_deadline.target_date,
    'created_at',p_deadline.created_at,
    'updated_at',p_deadline.updated_at
  )
$$;

create function private.rpc_impl_get_personal_deadline()
returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=private.current_principal_id();
  deadline public.personal_deadlines%rowtype;
begin
  if actor is null then return public.api_error('AUTH_REQUIRED'); end if;

  select * into deadline
  from public.personal_deadlines
  where user_id=actor;

  return public.api_ok(jsonb_build_object(
    'deadline',case when found then private.personal_deadline_json(deadline) else null end
  ));
end $$;

create function private.rpc_impl_set_personal_deadline(
  p_title text,p_target_date date,p_timezone text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=private.current_principal_id();
  normalized_title text:=btrim(p_title);
  local_today date;
  deadline public.personal_deadlines%rowtype;
begin
  if actor is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_title is null or char_length(normalized_title) not between 1 and 40 then
    return public.api_error('INVALID_DEADLINE_TITLE');
  end if;
  if p_timezone is null or not exists(
    select 1 from pg_catalog.pg_timezone_names where name=p_timezone
  ) then
    return public.api_error('INVALID_TIMEZONE');
  end if;

  local_today:=(pg_catalog.clock_timestamp() at time zone p_timezone)::date;
  if p_target_date is null or p_target_date<local_today then
    return public.api_error('INVALID_DEADLINE_DATE');
  end if;

  insert into public.personal_deadlines(user_id,title,target_date)
  values(actor,normalized_title,p_target_date)
  on conflict(user_id) do update set
    title=excluded.title,
    target_date=excluded.target_date,
    updated_at=pg_catalog.clock_timestamp()
  returning * into deadline;

  return public.api_ok(jsonb_build_object(
    'deadline',private.personal_deadline_json(deadline)
  ));
end $$;

create function public.get_personal_deadline()
returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  return private.rpc_impl_get_personal_deadline();
exception when others then
  return private.rpc_internal_error_envelope('get_personal_deadline',sqlstate);
end $$;

create function public.set_personal_deadline(
  p_title text,p_target_date date,p_timezone text
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  return private.rpc_impl_set_personal_deadline(p_title,p_target_date,p_timezone);
exception when others then
  return private.rpc_internal_error_envelope('set_personal_deadline',sqlstate);
end $$;

revoke all on function private.personal_deadline_json(public.personal_deadlines),
  private.rpc_impl_get_personal_deadline(),
  private.rpc_impl_set_personal_deadline(text,date,text)
from public,anon,authenticated;

revoke all on function public.get_personal_deadline(),
  public.set_personal_deadline(text,date,text)
from public,anon;

grant execute on function public.get_personal_deadline(),
  public.set_personal_deadline(text,date,text)
to authenticated;
