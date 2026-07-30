alter table public.spaces
  add column lifecycle_status text not null default 'active'
    check (lifecycle_status in ('active','dissolved')),
  add column dissolved_at timestamptz,
  add column dissolved_by uuid references auth.users(id),
  add constraint spaces_lifecycle_consistency check (
    (lifecycle_status = 'active' and dissolved_at is null and dissolved_by is null) or
    (lifecycle_status = 'dissolved' and dissolved_at is not null and dissolved_by is not null)
  );

alter table public.space_members add column end_reason text;
update public.space_members set end_reason = 'disabled' where status = 'disabled';
alter table public.space_members
  add constraint space_members_end_reason_check check (
    (status = 'active' and end_reason is null) or
    (status = 'disabled' and end_reason in ('disabled','left','dissolved'))
  );
alter table public.space_members drop constraint space_members_check1;

create function public.enforce_active_space_owner() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.role='owner' and new.status='disabled' and exists(
   select 1 from public.spaces s where s.id=new.space_id and s.lifecycle_status='active'
 ) then
  raise exception using errcode='23514',message='active space owner cannot be disabled';
 end if;
 return new;
end $$;
create trigger active_space_owner_cannot_be_disabled
before insert or update of role,status on public.space_members
for each row execute function public.enforce_active_space_owner();
revoke all on function public.enforce_active_space_owner() from public,anon,authenticated;

create or replace function public.current_user_is_active_member(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.space_members m
    join public.spaces s on s.id = m.space_id
    where m.space_id = p_space_id and m.user_id = auth.uid()
      and m.status = 'active' and s.lifecycle_status = 'active'
  )
$$;

create or replace function public.current_user_is_owner(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.space_members m
    join public.spaces s on s.id = m.space_id
    where m.space_id = p_space_id and m.user_id = auth.uid()
      and m.role = 'owner' and m.status = 'active' and s.lifecycle_status = 'active'
  )
$$;

create or replace function public.leave_space(p_space_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_space_id::text,''); cached jsonb; m public.space_members%rowtype; sid uuid; result jsonb; t timestamptz:=now();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'leave_space',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(h,0));
 select m0.* into m from public.space_members m0 join public.spaces s on s.id=m0.space_id
  where m0.space_id=p_space_id and m0.user_id=a and m0.status='active' and s.lifecycle_status='active' for update of m0;
 if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if m.role='owner' then return public.api_error('OWNER_MUST_TRANSFER_OR_DISSOLVE'); end if;
 select id into sid from public.focus_sessions where member_id=m.id and status in('focusing','paused') for update;
 if sid is not null then perform public.finish_focus_session(sid,t,'member_left'); end if;
 update public.goal_proposals gp set status='rejected',resolved_at=t
  where gp.status='pending' and exists(select 1 from public.goal_proposal_members gpm where gpm.proposal_id=gp.id and gpm.member_id=m.id);
 update public.space_members set status='disabled',disabled_at=t,disabled_by=a,end_reason='left' where id=m.id;
 result:=public.api_ok(jsonb_build_object('space_id',p_space_id,'member_id',m.id,'status','left','settled_session',case when sid is null then null else public.session_json(sid) end));
 return public.store_command(a,p_idempotency_key,'leave_space',h,sid,result);
end $$;

create or replace function public.transfer_ownership(p_space_id uuid,p_target_member_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_space_id::text,'')||'|'||coalesce(p_target_member_id::text,''); cached jsonb; current_owner public.space_members%rowtype; target public.space_members%rowtype; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'transfer_ownership',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(coalesce(p_space_id::text,''),0));
 perform 1 from public.spaces where id=p_space_id and lifecycle_status='active' for update;
 if not found or not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
 select * into current_owner from public.space_members where space_id=p_space_id and user_id=a and role='owner' and status='active' for update;
 select * into target from public.space_members where id=p_target_member_id and space_id=p_space_id and status='active' for update;
 if not found then return public.api_error('MEMBER_NOT_FOUND'); end if;
 if target.id=current_owner.id then return public.api_error('CANNOT_TRANSFER_TO_SELF'); end if;
 update public.space_members set role='member' where id=current_owner.id;
 update public.space_members set role='owner' where id=target.id;
 update public.spaces set owner_id=target.user_id where id=p_space_id;
 result:=public.api_ok(jsonb_build_object('space_id',p_space_id,'previous_owner_member_id',current_owner.id,'owner_member_id',target.id,'owner_user_id',target.user_id));
 return public.store_command(a,p_idempotency_key,'transfer_ownership',h,null,result);
end $$;

create or replace function public.dissolve_space(p_space_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_space_id::text,''); cached jsonb; result jsonb; t timestamptz:=now(); r record; settled int:=0;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'dissolve_space',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(h,0));
 perform 1 from public.spaces where id=p_space_id and lifecycle_status='active' for update;
 if not found or not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
 perform 1 from public.space_members where space_id=p_space_id and status='active' order by id for update;
 for r in select id from public.focus_sessions where space_id=p_space_id and status in('focusing','paused') order by id for update loop
  perform public.finish_focus_session(r.id,t,'space_dissolved'); settled:=settled+1;
 end loop;
 update public.goal_proposals set status='rejected',resolved_at=t where space_id=p_space_id and status='pending';
 update public.goals set status='failed',completed_at=t where space_id=p_space_id and status in('scheduled','active');
 update public.spaces set lifecycle_status='dissolved',dissolved_at=t,dissolved_by=a,invite_token_hash=public.invite_hash(public.new_invite_token()) where id=p_space_id;
 update public.space_members set status='disabled',disabled_at=t,disabled_by=a,end_reason='dissolved' where space_id=p_space_id and status='active';
 result:=public.api_ok(jsonb_build_object('space_id',p_space_id,'status','dissolved','dissolved_at',t,'settled_session_count',settled));
 return public.store_command(a,p_idempotency_key,'dissolve_space',h,null,result);
end $$;

revoke all on function public.leave_space(uuid,uuid),public.transfer_ownership(uuid,uuid,uuid),public.dissolve_space(uuid,uuid) from public,anon;
grant execute on function public.leave_space(uuid,uuid),public.transfer_ownership(uuid,uuid,uuid),public.dissolve_space(uuid,uuid) to authenticated;
