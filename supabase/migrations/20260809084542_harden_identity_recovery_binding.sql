-- Identity recovery is a security-sensitive ownership transfer. Serialize both
-- principals before validating the target, then validate again while its
-- binding row is locked so application activity cannot race the transfer.

create function private.lock_identity_pair(p_first uuid,p_second uuid) returns void
language plpgsql security definer set search_path='' as $$
declare
  first_key text:=least(p_first::text,p_second::text);
  second_key text:=greatest(p_first::text,p_second::text);
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(first_key,0));
  if second_key<>first_key then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(second_key,0));
  end if;
end $$;

create function private.auth_identity_is_pristine(p_auth_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select
    not exists(select 1 from public.profiles p where p.id=p_auth_user_id)
    and not exists(select 1 from public.space_members m where m.user_id=p_auth_user_id)
    and not exists(select 1 from public.spaces s where s.owner_id=p_auth_user_id)
    and not exists(select 1 from public.focus_sessions s where s.user_id=p_auth_user_id)
    and not exists(select 1 from public.focus_events e where e.actor_id=p_auth_user_id)
    and not exists(select 1 from public.focus_commands c where c.actor_id=p_auth_user_id)
    and not exists(select 1 from private.client_error_reports e where e.actor_id=p_auth_user_id)
    and not exists(select 1 from private.client_error_rate_limits r where r.actor_id=p_auth_user_id)
$$;

create function private.lock_identity_activity() returns trigger
language plpgsql security definer set search_path='' as $$
declare actor uuid;
begin
  actor:=nullif(to_jsonb(new)->>tg_argv[0],'')::uuid;
  if actor is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text,0));
  end if;
  return new;
end $$;

create trigger lock_profile_identity_activity
before insert or update of id on public.profiles
for each row execute function private.lock_identity_activity('id');
create trigger lock_space_identity_activity
before insert or update of owner_id on public.spaces
for each row execute function private.lock_identity_activity('owner_id');
create trigger lock_member_identity_activity
before insert or update of user_id on public.space_members
for each row execute function private.lock_identity_activity('user_id');
create trigger lock_focus_session_identity_activity
before insert or update of user_id on public.focus_sessions
for each row execute function private.lock_identity_activity('user_id');
create trigger lock_focus_event_identity_activity
before insert or update of actor_id on public.focus_events
for each row execute function private.lock_identity_activity('actor_id');
create trigger lock_focus_command_identity_activity
before insert or update of actor_id on public.focus_commands
for each row execute function private.lock_identity_activity('actor_id');
create trigger lock_client_error_identity_activity
before insert or update of actor_id on private.client_error_reports
for each row execute function private.lock_identity_activity('actor_id');
create trigger lock_client_error_rate_identity_activity
before insert or update of actor_id on private.client_error_rate_limits
for each row execute function private.lock_identity_activity('actor_id');

create table private.identity_binding_events(
  id bigint generated always as identity primary key,
  principal_user_id uuid not null references auth.users(id) on delete restrict,
  previous_auth_user_id uuid references auth.users(id) on delete restrict,
  new_auth_user_id uuid not null references auth.users(id) on delete restrict,
  recovery_kind text not null check(recovery_kind in('transfer','recovery')),
  credential_id uuid not null,
  occurred_at timestamptz not null default now()
);
create index identity_binding_events_principal_time
  on private.identity_binding_events(principal_user_id,occurred_at desc);
create index identity_binding_events_previous_auth
  on private.identity_binding_events(previous_auth_user_id) where previous_auth_user_id is not null;
create index identity_binding_events_new_auth
  on private.identity_binding_events(new_auth_user_id);

create or replace function public.redeem_identity_transfer_code(p_transfer_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  raw_actor uuid:=auth.uid();
  current_principal uuid:=private.current_principal_id();
  c private.identity_transfer_codes%rowtype;
  target_binding private.identity_bindings%rowtype;
  previous_auth uuid;
  changed integer;
  t timestamptz:=now();
begin
  if raw_actor is null or current_principal is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_transfer_code is null or p_transfer_code !~ '^[A-Za-z0-9_-]{32}$' then return public.api_error('INVALID_TRANSFER_CODE'); end if;
  select * into c from private.identity_transfer_codes where token_hash=private.identity_transfer_hash(p_transfer_code) for update;
  if not found then return public.api_error('INVALID_TRANSFER_CODE'); end if;
  if c.consumed_at is not null then return public.api_error('TRANSFER_CODE_USED'); end if;
  if c.expires_at<=t then
    update private.identity_transfer_codes set failed_attempts=least(10,failed_attempts+1) where id=c.id;
    return public.api_error('TRANSFER_CODE_EXPIRED');
  end if;
  if c.principal_user_id=current_principal then return public.api_error('CANNOT_TRANSFER_TO_SELF'); end if;

  perform private.lock_identity_pair(c.principal_user_id,raw_actor);
  select * into target_binding from private.identity_bindings
    where auth_user_id=raw_actor for update;
  if not found or not target_binding.active
    or target_binding.principal_user_id<>raw_actor
    or current_principal<>raw_actor
    or not private.auth_identity_is_pristine(raw_actor)
  then return public.api_error('TARGET_IDENTITY_NOT_EMPTY'); end if;

  select auth_user_id into previous_auth from private.identity_bindings
    where principal_user_id=c.principal_user_id and active for update;
  update private.identity_bindings set active=false,revoked_at=t
    where principal_user_id=c.principal_user_id and active;
  update private.identity_bindings
    set principal_user_id=c.principal_user_id,active=true,bound_at=t,revoked_at=null
    where auth_user_id=raw_actor and active and principal_user_id=raw_actor;
  get diagnostics changed=row_count;
  if changed<>1 then raise exception 'identity target changed during transfer' using errcode='40001'; end if;
  update private.identity_transfer_codes set consumed_at=t where id=c.id and consumed_at is null;
  get diagnostics changed=row_count;
  if changed<>1 then raise exception 'identity transfer credential changed during transfer' using errcode='40001'; end if;
  insert into private.identity_binding_events(
    principal_user_id,previous_auth_user_id,new_auth_user_id,recovery_kind,credential_id,occurred_at
  ) values(c.principal_user_id,previous_auth,raw_actor,'transfer',c.id,t);
  return public.api_ok(jsonb_build_object('transferred',true,'expires_at',c.expires_at));
end $$;

create or replace function public.redeem_identity_recovery_code(p_recovery_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  raw_actor uuid:=auth.uid();
  current_principal uuid:=private.current_principal_id();
  c private.identity_recovery_codes%rowtype;
  target_binding private.identity_bindings%rowtype;
  previous_auth uuid;
  changed integer;
  t timestamptz:=now();
  remaining integer;
begin
  if raw_actor is null or current_principal is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_recovery_code is null or p_recovery_code !~ '^[A-Za-z0-9_-]{22}$' then return public.api_error('INVALID_RECOVERY_CODE'); end if;
  select * into c from private.identity_recovery_codes
    where code_hash=private.identity_recovery_hash(p_recovery_code) for update;
  if not found or c.invalidated_at is not null then return public.api_error('INVALID_RECOVERY_CODE'); end if;
  if c.consumed_at is not null then return public.api_error('RECOVERY_CODE_USED'); end if;
  if c.principal_user_id=current_principal then return public.api_error('CANNOT_TRANSFER_TO_SELF'); end if;

  perform private.lock_identity_pair(c.principal_user_id,raw_actor);
  select * into target_binding from private.identity_bindings
    where auth_user_id=raw_actor for update;
  if not found or not target_binding.active
    or target_binding.principal_user_id<>raw_actor
    or current_principal<>raw_actor
    or not private.auth_identity_is_pristine(raw_actor)
  then return public.api_error('TARGET_IDENTITY_NOT_EMPTY'); end if;

  select auth_user_id into previous_auth from private.identity_bindings
    where principal_user_id=c.principal_user_id and active for update;
  update private.identity_bindings set active=false,revoked_at=t
    where principal_user_id=c.principal_user_id and active;
  update private.identity_bindings
    set principal_user_id=c.principal_user_id,active=true,bound_at=t,revoked_at=null
    where auth_user_id=raw_actor and active and principal_user_id=raw_actor;
  get diagnostics changed=row_count;
  if changed<>1 then raise exception 'identity target changed during recovery' using errcode='40001'; end if;
  update private.identity_recovery_codes set consumed_at=t where id=c.id and consumed_at is null;
  get diagnostics changed=row_count;
  if changed<>1 then raise exception 'identity recovery credential changed during recovery' using errcode='40001'; end if;
  insert into private.identity_binding_events(
    principal_user_id,previous_auth_user_id,new_auth_user_id,recovery_kind,credential_id,occurred_at
  ) values(c.principal_user_id,previous_auth,raw_actor,'recovery',c.id,t);
  select count(*)::integer into remaining from private.identity_recovery_codes
    where principal_user_id=c.principal_user_id and consumed_at is null and invalidated_at is null;
  return public.api_ok(jsonb_build_object('transferred',true,'remaining_recovery_codes',remaining));
end $$;

revoke all on table private.identity_binding_events from public,anon,authenticated;
revoke all on function private.lock_identity_pair(uuid,uuid),private.auth_identity_is_pristine(uuid),private.lock_identity_activity() from public,anon,authenticated;
revoke all on function public.redeem_identity_transfer_code(text),public.redeem_identity_recovery_code(text) from public,anon;
grant execute on function public.redeem_identity_transfer_code(text),public.redeem_identity_recovery_code(text) to authenticated;
