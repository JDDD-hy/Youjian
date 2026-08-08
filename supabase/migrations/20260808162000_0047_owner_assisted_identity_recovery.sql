-- Let a room owner restore an active member whose device-local anonymous Auth
-- session was lost. The recovery reuses the existing one-time transfer path so
-- the stable principal, member id, history, join order, and achievements remain
-- unchanged, while every older binding is revoked on redemption.

create function public.create_member_recovery_code(
  p_space_id uuid,
  p_member_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=private.current_principal_id();
  owner_membership public.space_members%rowtype;
  target public.space_members%rowtype;
  token text;
  t timestamptz:=now();
begin
  if actor is null then return public.api_error('AUTH_REQUIRED'); end if;
  select * into owner_membership from public.space_members
    where space_id=p_space_id and user_id=actor and status='active';
  if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if owner_membership.role<>'owner' then return public.api_error('NOT_SPACE_OWNER'); end if;

  select * into target from public.space_members
    where id=p_member_id and space_id=p_space_id and status='active' for update;
  if not found then return public.api_error('MEMBER_NOT_FOUND'); end if;
  if target.user_id=actor then return public.api_error('CANNOT_TRANSFER_TO_SELF'); end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target.user_id::text,0)
  );
  update private.identity_transfer_codes set consumed_at=t
    where principal_user_id=target.user_id and consumed_at is null;
  token:=rtrim(translate(encode(extensions.gen_random_bytes(24),'base64'),'+/','-_'),'=');
  insert into private.identity_transfer_codes(
    principal_user_id,token_hash,created_at,expires_at
  ) values(
    target.user_id,private.identity_transfer_hash(token),t,t+interval '10 minutes'
  );
  return public.api_ok(jsonb_build_object(
    'transfer_code',token,
    'expires_at',t+interval '10 minutes',
    'member',jsonb_build_object(
      'member_id',target.id,
      'display_name',target.display_name
    )
  ));
end $$;

revoke all on function public.create_member_recovery_code(uuid,uuid) from public,anon;
grant execute on function public.create_member_recovery_code(uuid,uuid) to authenticated;
