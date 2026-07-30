insert into private.app_secrets(name,secret)
values('identity_transfer_hmac_key',extensions.gen_random_bytes(32))
on conflict(name) do nothing;

create table private.identity_bindings(
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  principal_user_id uuid not null references auth.users(id) on delete restrict,
  active boolean not null default true,
  bound_at timestamptz not null default now(),
  revoked_at timestamptz,
  check ((active and revoked_at is null) or (not active and revoked_at is not null))
);
create unique index one_active_identity_per_principal
  on private.identity_bindings(principal_user_id) where active;

insert into private.identity_bindings(auth_user_id,principal_user_id)
select id,id from auth.users on conflict(auth_user_id) do nothing;

create function private.bind_new_auth_identity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into private.identity_bindings(auth_user_id,principal_user_id) values(new.id,new.id)
 on conflict(auth_user_id) do nothing;
 return new;
end $$;
create trigger bind_new_auth_identity
after insert on auth.users for each row execute function private.bind_new_auth_identity();

create function private.current_principal_id() returns uuid
language sql stable security definer set search_path='' as $$
 select b.principal_user_id from private.identity_bindings b
 where b.auth_user_id=auth.uid() and b.active
$$;
revoke all on function private.bind_new_auth_identity(),private.current_principal_id() from public,anon,authenticated;

-- Existing RPCs and RLS helpers consistently resolve the stable application
-- principal instead of trusting the replaceable Supabase Auth user id.
do $$
declare r record; definition text;
begin
 for r in
  select p.oid from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname in('public','private') and p.prokind='f'
    and not(n.nspname='private' and p.proname='current_principal_id')
    and pg_catalog.pg_get_functiondef(p.oid) like '%auth.uid()%'
 loop
  definition:=replace(pg_catalog.pg_get_functiondef(r.oid),'auth.uid()','private.current_principal_id()');
  execute definition;
 end loop;
end $$;

create table private.identity_transfer_codes(
  id uuid primary key default gen_random_uuid(),
  principal_user_id uuid not null references auth.users(id) on delete restrict,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  failed_attempts smallint not null default 0 check(failed_attempts between 0 and 10),
  check(expires_at>created_at),
  check(consumed_at is null or consumed_at>=created_at)
);
create index identity_transfer_codes_principal_active
  on private.identity_transfer_codes(principal_user_id,expires_at desc) where consumed_at is null;

create function private.identity_transfer_hash(p_token text) returns text
language sql stable security definer set search_path='' as $$
 select encode(extensions.hmac(convert_to(p_token,'UTF8'),s.secret,'sha256'),'hex')
 from private.app_secrets s where s.name='identity_transfer_hmac_key'
$$;
revoke all on table private.identity_bindings,private.identity_transfer_codes from public,anon,authenticated;
revoke all on function private.identity_transfer_hash(text) from public,anon,authenticated;

create function public.create_identity_transfer_code() returns jsonb
language plpgsql security definer set search_path='' as $$
declare raw_actor uuid:=auth.uid(); principal uuid:=private.current_principal_id(); token text; t timestamptz:=now();
begin
 if raw_actor is null or principal is null then return public.api_error('AUTH_REQUIRED'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(principal::text,0));
 update private.identity_transfer_codes set consumed_at=t
  where principal_user_id=principal and consumed_at is null;
 token:=rtrim(translate(encode(extensions.gen_random_bytes(24),'base64'),'+/','-_'),'=');
 insert into private.identity_transfer_codes(principal_user_id,token_hash,created_at,expires_at)
 values(principal,private.identity_transfer_hash(token),t,t+interval '10 minutes');
 return public.api_ok(jsonb_build_object('transfer_code',token,'expires_at',t+interval '10 minutes'));
end $$;

create function public.redeem_identity_transfer_code(p_transfer_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare raw_actor uuid:=auth.uid(); current_principal uuid:=private.current_principal_id(); c private.identity_transfer_codes%rowtype; t timestamptz:=now();
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
 if current_principal<>raw_actor
   or exists(select 1 from public.profiles where id=current_principal)
   or exists(select 1 from public.space_members where user_id=current_principal)
   or exists(select 1 from public.spaces where owner_id=current_principal)
   or exists(select 1 from public.focus_commands where actor_id=current_principal)
 then return public.api_error('TARGET_IDENTITY_NOT_EMPTY'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(c.principal_user_id::text,0));
 update private.identity_bindings set active=false,revoked_at=t
  where auth_user_id=raw_actor and active;
 update private.identity_bindings set active=false,revoked_at=t
  where principal_user_id=c.principal_user_id and active;
 update private.identity_bindings set principal_user_id=c.principal_user_id,active=true,bound_at=t,revoked_at=null
  where auth_user_id=raw_actor;
 update private.identity_transfer_codes set consumed_at=t where id=c.id;
 return public.api_ok(jsonb_build_object('transferred',true,'expires_at',c.expires_at));
end $$;

revoke all on function public.create_identity_transfer_code(),public.redeem_identity_transfer_code(text) from public,anon;
grant execute on function public.create_identity_transfer_code(),public.redeem_identity_transfer_code(text) to authenticated;
