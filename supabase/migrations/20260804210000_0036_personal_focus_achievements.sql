-- Personal, cross-space focus achievements with immutable per-session awards.

alter table public.focus_sessions
  add column timezone_snapshot text;

alter table public.focus_sessions disable trigger settled_focus_sessions_are_immutable;
update public.focus_sessions s
set timezone_snapshot=p.timezone
from public.profiles p
where p.id=s.user_id and s.timezone_snapshot is null;
alter table public.focus_sessions enable trigger settled_focus_sessions_are_immutable;

alter table public.focus_sessions
  alter column timezone_snapshot set not null;

create table public.personal_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_type text not null check (achievement_type in ('night_owl','solo_focus')),
  first_earned_at timestamptz not null,
  last_earned_at timestamptz not null,
  count integer not null default 1 check (count > 0),
  tier text not null check (tier in ('bronze','silver','gold')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  primary key (user_id,achievement_type),
  check (last_earned_at>=first_earned_at)
);

create table public.personal_achievement_awards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_type text not null check (achievement_type in ('night_owl','solo_focus')),
  source_space_id uuid not null references public.spaces(id) on delete restrict,
  source_session_id uuid not null references public.focus_sessions(id) on delete restrict,
  earned_at timestamptz not null,
  unique (achievement_type,source_session_id)
);

create index personal_achievement_awards_user_earned
  on public.personal_achievement_awards(user_id,earned_at desc,id desc);

alter table public.personal_achievements enable row level security;
alter table public.personal_achievement_awards enable row level security;

create policy personal_achievements_select_own
on public.personal_achievements for select to authenticated
using (user_id=auth.uid());

create policy personal_achievement_awards_select_own
on public.personal_achievement_awards for select to authenticated
using (user_id=auth.uid());

revoke all on public.personal_achievements,public.personal_achievement_awards from public,anon,authenticated;
grant select on public.personal_achievements,public.personal_achievement_awards to authenticated;

create function private.snapshot_focus_timezone() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  select timezone into new.timezone_snapshot from public.profiles where id=new.user_id;
  if new.timezone_snapshot is null or not exists(
    select 1 from pg_catalog.pg_timezone_names where name=new.timezone_snapshot
  ) then
    raise exception using errcode='22023',message='invalid focus timezone';
  end if;
  return new;
end $$;

create trigger focus_sessions_snapshot_timezone
before insert on public.focus_sessions
for each row execute function private.snapshot_focus_timezone();

create function private.lock_focus_space() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_session_id uuid; v_space_id uuid;
begin
  v_session_id:=case when tg_table_name='focus_segments' then new.session_id else new.id end;
  select space_id into v_space_id from public.focus_sessions where id=v_session_id;
  if v_space_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_space_id::text,36));
  end if;
  return new;
end $$;

create trigger focus_segments_lock_space
before insert on public.focus_segments
for each row execute function private.lock_focus_space();

create trigger focus_sessions_lock_space_before_final
before update of status on public.focus_sessions
for each row when (old.status in ('focusing','paused') and new.status in ('completed','discarded'))
execute function private.lock_focus_space();

create function private.record_personal_achievement(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_earned_at timestamptz
) returns boolean language plpgsql security definer set search_path='' as $$
declare inserted_id uuid;
begin
  insert into public.personal_achievement_awards(
    user_id,achievement_type,source_space_id,source_session_id,earned_at
  ) values(p_user_id,p_type,p_space_id,p_session_id,p_earned_at)
  on conflict(achievement_type,source_session_id) do nothing
  returning id into inserted_id;
  if inserted_id is null then return false; end if;

  insert into public.personal_achievements(
    user_id,achievement_type,first_earned_at,last_earned_at,count,tier
  ) values(
    p_user_id,p_type,p_earned_at,p_earned_at,1,
    case when p_type='night_owl' then 'gold' else 'bronze' end
  )
  on conflict(user_id,achievement_type) do update set
    last_earned_at=greatest(public.personal_achievements.last_earned_at,excluded.last_earned_at),
    first_earned_at=least(public.personal_achievements.first_earned_at,excluded.first_earned_at),
    count=public.personal_achievements.count+1,
    tier=case
      when excluded.achievement_type='night_owl' then 'gold'
      when public.personal_achievements.count+1>=20 then 'gold'
      when public.personal_achievements.count+1>=5 then 'silver'
      else 'bronze'
    end;
  return true;
end $$;

create function private.evaluate_personal_focus_achievements() returns trigger
language plpgsql security definer set search_path='' as $$
declare effective_seconds integer; local_start timestamp; local_end timestamp; has_overlap boolean;
begin
  if new.status<>'completed' or old.status in ('completed','discarded') then return new; end if;

  select coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::integer
  into effective_seconds from public.focus_segments
  where session_id=new.id and ended_at is not null;
  if effective_seconds<3600 then return new; end if;

  local_start:=new.started_at at time zone new.timezone_snapshot;
  local_end:=new.completed_at at time zone new.timezone_snapshot;
  if extract(hour from local_start)=23 and local_end::date>local_start::date then
    perform private.record_personal_achievement(
      new.user_id,'night_owl',new.space_id,new.id,new.completed_at
    );
  end if;

  select exists(
    select 1
    from public.focus_segments mine
    join public.focus_sessions other_session
      on other_session.space_id=new.space_id and other_session.user_id<>new.user_id
    join public.focus_segments other on other.session_id=other_session.id
    where mine.session_id=new.id and mine.ended_at is not null
      and other.started_at<mine.ended_at
      and coalesce(other.ended_at,new.completed_at)>mine.started_at
  ) into has_overlap;
  if not has_overlap then
    perform private.record_personal_achievement(
      new.user_id,'solo_focus',new.space_id,new.id,new.completed_at
    );
  end if;
  return new;
end $$;

create trigger focus_sessions_evaluate_personal_achievements
after update of status on public.focus_sessions
for each row when (old.status in ('focusing','paused') and new.status='completed')
execute function private.evaluate_personal_focus_achievements();

create function private.rpc_impl_list_personal_achievements(
  p_space_id uuid,p_limit integer,p_cursor text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); cursor_time timestamptz; cursor_type text; items jsonb; next_cursor text;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  if p_cursor is not null then begin
    cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz;
    cursor_type:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2);
  exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
  with rows as (
    select pa.*,row_number() over(order by last_earned_at desc,achievement_type desc) rn
    from public.personal_achievements pa where user_id=a
      and (p_cursor is null or (last_earned_at,achievement_type)<(cursor_time,cursor_type))
    order by last_earned_at desc,achievement_type desc limit p_limit+1
  ),chosen as(select * from rows where rn<=p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',achievement_type,'achievement_type',achievement_type,'tier',tier,
    'earned_at',first_earned_at,'first_earned_at',first_earned_at,
    'last_earned_at',last_earned_at,'count',count,'metadata',metadata,'seen',true
  ) order by last_earned_at desc,achievement_type desc),'[]'),
  case when(select count(*) from rows)>p_limit then (
    select encode(convert_to(last_earned_at::text||'|'||achievement_type,'UTF8'),'base64')
    from chosen order by last_earned_at,achievement_type limit 1
  ) end into items,next_cursor from chosen;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',next_cursor));
end $$;

create function public.list_personal_achievements(
  p_space_id uuid,p_limit integer default 30,p_cursor text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  return private.rpc_impl_list_personal_achievements(p_space_id,p_limit,p_cursor);
exception when others then
  return private.rpc_internal_error_envelope('list_personal_achievements',sqlstate);
end $$;

revoke all on function private.snapshot_focus_timezone(),private.lock_focus_space(),
  private.record_personal_achievement(uuid,text,uuid,uuid,timestamptz),
  private.evaluate_personal_focus_achievements(),
  private.rpc_impl_list_personal_achievements(uuid,integer,text)
from public,anon,authenticated;
revoke all on function public.list_personal_achievements(uuid,integer,text) from public;
grant execute on function public.list_personal_achievements(uuid,integer,text) to authenticated;
