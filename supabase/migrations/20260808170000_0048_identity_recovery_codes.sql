-- Long-lived, one-time recovery codes protect every anonymous identity,
-- including a room owner, without relying on a still-working old device.

create table private.identity_recovery_codes(
  id uuid primary key default gen_random_uuid(),
  principal_user_id uuid not null references auth.users(id) on delete restrict,
  code_hash text not null unique,
  generation_id uuid not null,
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  invalidated_at timestamptz,
  check(consumed_at is null or consumed_at>=created_at),
  check(invalidated_at is null or invalidated_at>=created_at),
  check(not(consumed_at is not null and invalidated_at is not null))
);
create index identity_recovery_codes_principal_active
  on private.identity_recovery_codes(principal_user_id,created_at desc)
  where consumed_at is null and invalidated_at is null;

create function private.identity_recovery_hash(p_code text) returns text
language sql stable security definer set search_path='' as $$
 select encode(extensions.hmac(convert_to('recovery:'||p_code,'UTF8'),s.secret,'sha256'),'hex')
 from private.app_secrets s where s.name='identity_transfer_hmac_key'
$$;

create function public.rotate_identity_recovery_codes() returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  principal uuid:=private.current_principal_id();
  generation uuid:=gen_random_uuid();
  code text;
  codes jsonb:='[]'::jsonb;
  t timestamptz:=now();
begin
  if principal is null then return public.api_error('AUTH_REQUIRED'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(principal::text,0));
  update private.identity_recovery_codes set invalidated_at=t
    where principal_user_id=principal and consumed_at is null and invalidated_at is null;
  for i in 1..8 loop
    code:=rtrim(translate(encode(extensions.gen_random_bytes(16),'base64'),'+/','-_'),'=');
    insert into private.identity_recovery_codes(
      principal_user_id,code_hash,generation_id,created_at
    ) values(principal,private.identity_recovery_hash(code),generation,t);
    codes:=codes||jsonb_build_array(code);
  end loop;
  return public.api_ok(jsonb_build_object(
    'codes',codes,'generated_at',t,'generation_id',generation
  ));
end $$;

create function public.redeem_identity_recovery_code(p_recovery_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  raw_actor uuid:=auth.uid();
  current_principal uuid:=private.current_principal_id();
  c private.identity_recovery_codes%rowtype;
  t timestamptz:=now();
  remaining integer;
begin
  if raw_actor is null or current_principal is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_recovery_code is null or p_recovery_code !~ '^[A-Za-z0-9_-]{22}$' then
    return public.api_error('INVALID_RECOVERY_CODE');
  end if;
  select * into c from private.identity_recovery_codes
    where code_hash=private.identity_recovery_hash(p_recovery_code) for update;
  if not found or c.invalidated_at is not null then return public.api_error('INVALID_RECOVERY_CODE'); end if;
  if c.consumed_at is not null then return public.api_error('RECOVERY_CODE_USED'); end if;
  if c.principal_user_id=current_principal then return public.api_error('CANNOT_TRANSFER_TO_SELF'); end if;
  if current_principal<>raw_actor
    or exists(select 1 from public.profiles where id=current_principal)
    or exists(select 1 from public.space_members where user_id=current_principal)
    or exists(select 1 from public.spaces where owner_id=current_principal)
    or exists(select 1 from public.focus_commands where actor_id=current_principal)
  then return public.api_error('TARGET_IDENTITY_NOT_EMPTY'); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(c.principal_user_id::text,0)
  );
  update private.identity_bindings set active=false,revoked_at=t
    where auth_user_id=raw_actor and active;
  update private.identity_bindings set active=false,revoked_at=t
    where principal_user_id=c.principal_user_id and active;
  update private.identity_bindings
    set principal_user_id=c.principal_user_id,active=true,bound_at=t,revoked_at=null
    where auth_user_id=raw_actor;
  update private.identity_recovery_codes set consumed_at=t where id=c.id;
  select count(*)::integer into remaining from private.identity_recovery_codes
    where principal_user_id=c.principal_user_id
      and consumed_at is null and invalidated_at is null;
  return public.api_ok(jsonb_build_object(
    'transferred',true,'remaining_recovery_codes',remaining
  ));
end $$;

revoke all on table private.identity_recovery_codes from public,anon,authenticated;
revoke all on function private.identity_recovery_hash(text) from public,anon,authenticated;
revoke all on function public.rotate_identity_recovery_codes(),public.redeem_identity_recovery_code(text) from public,anon;
grant execute on function public.rotate_identity_recovery_codes(),public.redeem_identity_recovery_code(text) to authenticated;
