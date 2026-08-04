-- Profile timezone values are already validated at their write boundary. Avoid
-- scanning pg_timezone_names once per row during bulk session imports.

create or replace function private.snapshot_focus_timezone() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  select timezone into new.timezone_snapshot from public.profiles where id=new.user_id;
  if new.timezone_snapshot is null then
    raise exception using errcode='22023',message='invalid focus timezone';
  end if;
  return new;
end $$;

revoke all on function private.snapshot_focus_timezone() from public,anon,authenticated;
