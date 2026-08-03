-- Mutable owner settings, rolling goal periods, and achievement provenance.

alter table public.achievements
  add column tier text not null default 'bronze'
    check (tier in ('bronze','silver','gold')),
  add column participants_recorded boolean not null default false;

create table public.achievement_participants (
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  member_id uuid not null references public.space_members(id),
  display_name_snapshot text not null,
  participation_days integer not null default 1 check (participation_days > 0),
  primary key (achievement_id, member_id)
);

alter table public.achievement_participants enable row level security;
revoke all on public.achievement_participants from public, anon, authenticated;

update public.achievements
set tier = case
  when achievement_type='focus_milestone' and coalesce((metadata->>'threshold_minutes')::int,0)>=6000 then 'gold'
  when achievement_type='focus_milestone' and coalesce((metadata->>'threshold_minutes')::int,0)>=3000 then 'silver'
  when achievement_type='three_days_together' then 'silver'
  else 'bronze'
end;

-- Old goal participant snapshots are reliable, so preserve them during upgrade.
insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
select a.id,gp.member_id,m.display_name
from public.achievements a
join public.goals g on g.id=(a.metadata->>'goal_id')::uuid
join public.goal_participants gp on gp.goal_id=g.id
join public.space_members m on m.id=gp.member_id
where a.achievement_type='first_goal'
on conflict do nothing;

update public.achievements a set participants_recorded=true
where a.achievement_type='first_goal'
  and exists(select 1 from public.achievement_participants ap where ap.achievement_id=a.id);

create or replace function public.next_goal_period(
  p_timezone text,
  p_period public.period_type,
  p_at timestamptz default now()
) returns tstzrange
language plpgsql stable security definer set search_path='' as $$
declare
  start_local timestamp:=date_trunc('day',p_at at time zone p_timezone)+interval '1 day';
  end_local timestamp;
begin
  if p_period='daily' then end_local:=start_local+interval '1 day';
  elsif p_period='weekly' then end_local:=start_local+interval '7 days';
  else end_local:=start_local+interval '1 month';
  end if;
  return tstzrange(start_local at time zone p_timezone,end_local at time zone p_timezone,'[)');
end $$;

create or replace function public.accept_proposal_if_ready(
  p_proposal_id uuid,
  p_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.goal_proposals%rowtype; bounds tstzrange; gid uuid;
begin
  select * into p from public.goal_proposals where id=p_proposal_id for update;
  if not found or p.status<>'pending' or exists(
    select 1 from public.goal_proposal_members
    where proposal_id=p.id and vote is distinct from 'accepted'
  ) then return null; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p.space_id::text,0));
  if exists(select 1 from public.goals where space_id=p.space_id and status in('scheduled','active')) then
    raise exception using errcode='P0001',message='GOAL_ALREADY_OPEN';
  end if;
  bounds:=public.next_goal_period((select timezone from public.spaces where id=p.space_id),p.period_type,p_at);
  update public.goal_proposals set status='accepted',resolved_at=p_at,effective_period_start=lower(bounds) where id=p.id;
  gid:=gen_random_uuid();
  insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status)
  values(gid,p.id,p.space_id,p.goal_type,p.period_type,p.target_value,lower(bounds),upper(bounds),'scheduled');
  insert into public.goal_participants(goal_id,member_id)
  select gid,member_id from public.goal_proposal_members where proposal_id=p.id;
  return gid;
end $$;

create or replace function private.rpc_impl_propose_goal(
  p_space_id uuid,p_goal_type text,p_period_type text,p_target_value integer,p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; gt public.goal_type; pt public.period_type; bounds tstzrange; pid uuid; h text; cached jsonb; result jsonb; member_count int;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
  h:=encode(extensions.digest(convert_to(coalesce(p_space_id::text,'')||'|'||coalesce(p_goal_type,'')||'|'||coalesce(p_period_type,'')||'|'||coalesce(p_target_value::text,''),'UTF8'),'sha256'),'hex');
  cached:=public.command_cached(a,p_idempotency_key,'propose_goal',h); if cached is not null then return cached; end if;
  begin gt:=p_goal_type::public.goal_type; exception when invalid_text_representation then return public.api_error('INVALID_GOAL_TYPE'); end;
  begin pt:=p_period_type::public.period_type; exception when invalid_text_representation then return public.api_error('INVALID_PERIOD_TYPE'); end;
  if gt is null then return public.api_error('INVALID_GOAL_TYPE'); end if;
  if pt is null then return public.api_error('INVALID_PERIOD_TYPE'); end if;
  if p_target_value is null or p_target_value<1 or p_target_value>1000000 or
    (gt='shared_checkin_days' and ((pt='daily' and p_target_value>1) or(pt='weekly' and p_target_value>7)or(pt='monthly' and p_target_value>31)))
  then return public.api_error('INVALID_TARGET_VALUE'); end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
  select * into m from public.space_members where space_id=p_space_id and user_id=a;
  if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
  if exists(select 1 from public.goal_proposals where space_id=p_space_id and status='pending') or
     exists(select 1 from public.goals where space_id=p_space_id and status in('scheduled','active'))
  then return public.api_error('GOAL_ALREADY_OPEN'); end if;
  select count(*) into member_count from public.space_members where space_id=p_space_id and status='active';
  if member_count<2 then return public.api_error('NOT_ENOUGH_MEMBERS'); end if;
  bounds:=public.next_goal_period((select timezone from public.spaces where id=p_space_id),pt,now()); pid:=gen_random_uuid();
  insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start)
  values(pid,p_space_id,m.id,gt,pt,p_target_value,'pending',now()+interval '48 hours',lower(bounds));
  insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at)
  select pid,id,case when id=m.id then 'accepted'::public.goal_vote end,case when id=m.id then now() end
  from public.space_members where space_id=p_space_id and status='active';
  result:=public.api_ok(jsonb_build_object('proposal',public.proposal_json(pid,m.id),'goal',null));
  return public.store_command(a,p_idempotency_key,'propose_goal',h,null,result);
exception when numeric_value_out_of_range or check_violation or not_null_violation then return public.api_error('INVALID_TARGET_VALUE');
end $$;

create function private.rpc_impl_update_space_name(
  p_space_id uuid,p_name text,p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text; cached jsonb; normalized text; result jsonb;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
  normalized:=btrim(coalesce(p_name,''));
  if char_length(normalized) not between 1 and 30 then return public.api_error('INVALID_SPACE_NAME'); end if;
  h:=coalesce(p_space_id::text,'')||'|'||normalized;
  cached:=public.command_cached(a,p_idempotency_key,'update_space_name',h); if cached is not null then return cached; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
  if not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
  update public.spaces set name=normalized where id=p_space_id;
  result:=public.api_ok(jsonb_build_object('space',jsonb_build_object('id',p_space_id,'name',normalized)));
  return public.store_command(a,p_idempotency_key,'update_space_name',h,null,result);
end $$;

create function private.rpc_impl_increase_member_limit(
  p_space_id uuid,p_member_limit smallint,p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text; cached jsonb; current_limit smallint; result jsonb;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
  if p_member_limit is null or p_member_limit not between 2 and 12 then return public.api_error('INVALID_MEMBER_LIMIT'); end if;
  h:=coalesce(p_space_id::text,'')||'|'||p_member_limit::text;
  cached:=public.command_cached(a,p_idempotency_key,'increase_member_limit',h); if cached is not null then return cached; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
  if not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
  select member_limit into current_limit from public.spaces where id=p_space_id for update;
  if p_member_limit<=current_limit then return public.api_error('MEMBER_LIMIT_NOT_INCREASED'); end if;
  update public.spaces set member_limit=p_member_limit where id=p_space_id;
  result:=public.api_ok(jsonb_build_object('space',jsonb_build_object('id',p_space_id,'member_limit',p_member_limit),'previous_member_limit',current_limit));
  return public.store_command(a,p_idempotency_key,'increase_member_limit',h,null,result);
end $$;

create or replace function private.rpc_impl_get_space_settings(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.spaces%rowtype; m public.space_members%rowtype; tz text; members jsonb; owner boolean;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  select * into s from public.spaces where id=p_space_id;
  select * into m from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active';
  select timezone into tz from public.profiles where id=auth.uid(); owner:=m.role='owner';
  select coalesce(jsonb_agg(jsonb_build_object('member_id',id,'display_name',display_name,'role',role,'status',status,'joined_at',joined_at) order by joined_at),'[]') into members
  from public.space_members where space_id=p_space_id;
  return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',s.id,'name',s.name,'timezone',s.timezone,'member_limit',s.member_limit,'daily_checkin_target_minutes',s.daily_checkin_target_minutes,'created_at',s.created_at),
    'me',jsonb_build_object('member_id',m.id,'display_name',m.display_name,'role',m.role,'profile_timezone',tz),'members',members,
    'owner_actions',jsonb_build_object('can_copy_invite',owner,'can_rotate_invite',owner,'can_disable_members',owner,'can_update_space_name',owner,'can_increase_member_limit',owner and s.member_limit<12)));
end $$;

create or replace function private.rpc_impl_list_achievements(p_space_id uuid,p_limit integer,p_cursor text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cursor_time timestamptz; cursor_id uuid; items jsonb; next_cursor text; v_member_id uuid;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  if p_cursor is not null then begin
    cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz;
    cursor_id:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2)::uuid;
  exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
  select id into v_member_id from public.space_members where space_id=p_space_id and user_id=auth.uid() and status='active';
  with rows as (
    select a.*,row_number() over(order by earned_at desc,id desc) rn
    from public.achievements a where space_id=p_space_id
      and achievement_type not in('together_lit','three_days_together','first_goal')
      and (p_cursor is null or (earned_at,id)<(cursor_time,cursor_id))
    order by earned_at desc,id desc limit p_limit+1
  ), chosen as(select * from rows where rn<=p_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',id,'achievement_type',achievement_type,'tier',tier,'earned_at',earned_at,'metadata',metadata,
    'participants_recorded',participants_recorded,
    'participants',(select coalesce(jsonb_agg(jsonb_build_object('member_id',ap.member_id,'display_name',ap.display_name_snapshot,'participation_days',ap.participation_days) order by ap.display_name_snapshot),'[]') from public.achievement_participants ap where ap.achievement_id=chosen.id),
    'seen',exists(select 1 from public.achievement_reads ar where ar.achievement_id=id and ar.member_id=v_member_id)
  ) order by earned_at desc,id desc),'[]'),
  case when (select count(*) from rows)>p_limit then (select encode(convert_to(earned_at::text||'|'||id::text,'UTF8'),'base64') from chosen order by earned_at,id limit 1) end
  into items,next_cursor from chosen;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',next_cursor));
end $$;

create function public.update_space_name(p_space_id uuid,p_name text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$begin
  return private.rpc_impl_update_space_name(p_space_id,p_name,p_idempotency_key);
exception when others then return private.rpc_internal_error_envelope('update_space_name',sqlstate); end$$;

create function public.increase_member_limit(p_space_id uuid,p_member_limit smallint,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$begin
  return private.rpc_impl_increase_member_limit(p_space_id,p_member_limit,p_idempotency_key);
exception when others then return private.rpc_internal_error_envelope('increase_member_limit',sqlstate); end$$;

revoke all on function public.update_space_name(uuid,text,uuid),public.increase_member_limit(uuid,smallint,uuid) from public;
grant execute on function public.update_space_name(uuid,text,uuid),public.increase_member_limit(uuid,smallint,uuid) to authenticated;
revoke all on function private.rpc_impl_update_space_name(uuid,text,uuid),private.rpc_impl_increase_member_limit(uuid,smallint,uuid) from public,anon,authenticated;
