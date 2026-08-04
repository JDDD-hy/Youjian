-- Use table-specific trigger functions so each NEW record is type-safe.

drop trigger focus_segments_lock_space on public.focus_segments;
drop trigger focus_sessions_lock_space_before_final on public.focus_sessions;
drop function private.lock_focus_space();

create function private.lock_focus_segment_space() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_space_id uuid;
begin
  select space_id into v_space_id from public.focus_sessions where id=new.session_id;
  if v_space_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_space_id::text,36));
  end if;
  return new;
end $$;

create function private.lock_focus_session_space() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.space_id::text,36));
  return new;
end $$;

create trigger focus_segments_lock_space
before insert on public.focus_segments
for each row execute function private.lock_focus_segment_space();

create trigger focus_sessions_lock_space_before_final
before update of status on public.focus_sessions
for each row when (old.status in ('focusing','paused') and new.status in ('completed','discarded'))
execute function private.lock_focus_session_space();

revoke all on function private.lock_focus_segment_space(),private.lock_focus_session_space()
from public,anon,authenticated;
