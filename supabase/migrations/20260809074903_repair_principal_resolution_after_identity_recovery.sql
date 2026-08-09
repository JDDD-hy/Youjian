-- Later feature migrations replaced several RPC implementations after the
-- identity-transfer migration had rewritten auth.uid() to the stable app
-- principal. Repair every non-authentication function in the final schema so
-- recovered devices resolve the same profile, membership, sessions, goals,
-- stats, settings, and achievements as the original device.
do $$
declare
  r record;
  definition text;
begin
  for r in
    select p.oid
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','private')
      and p.prokind='f'
      and pg_catalog.pg_get_functiondef(p.oid) like '%auth.uid()%'
      and not (n.nspname='private' and p.proname='current_principal_id')
      and not (
        n.nspname='public'
        and p.proname in (
          'create_identity_transfer_code',
          'redeem_identity_transfer_code',
          'redeem_identity_recovery_code'
        )
      )
  loop
    definition:=replace(
      pg_catalog.pg_get_functiondef(r.oid),
      'auth.uid()',
      'private.current_principal_id()'
    );
    execute definition;
  end loop;
end $$;

-- Force every PostgREST instance to refresh the repaired function metadata.
select pg_catalog.pg_notification_queue_usage();
notify pgrst, 'reload schema';
