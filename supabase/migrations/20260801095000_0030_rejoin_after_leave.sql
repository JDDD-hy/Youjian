create or replace function private.rpc_impl_join_space(p_invite_token text,p_display_name text,p_profile_timezone text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=private.current_principal_id(); h text; cached jsonb; s public.spaces%rowtype; existing public.space_members%rowtype; mid uuid; n int; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_invite_token,'')||'|'||coalesce(p_display_name,'')||'|'||coalesce(p_profile_timezone,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'join_space',h); if cached is not null then return cached; end if;
 select * into s from public.spaces where invite_token_hash=public.invite_hash(p_invite_token) and lifecycle_status='active' for update;
 if not found then return public.api_error('INVITE_INVALID'); end if;
 select * into existing from public.space_members where user_id=a and space_id=s.id for update;
 if found and existing.status='active' then
  return public.api_error('ALREADY_IN_SPACE','{}',jsonb_build_object('membership',jsonb_build_object('member_id',existing.id,'space_id',s.id,'display_name',existing.display_name,'role',existing.role,'status',existing.status)));
 end if;
 if found and coalesce(existing.end_reason,'disabled')<>'left' then return public.api_error('MEMBER_DISABLED'); end if;
 if exists(select 1 from public.space_members where user_id=a and status='active') then return public.api_error('ALREADY_IN_ANOTHER_SPACE'); end if;
 if not public.validate_iana_timezone(p_profile_timezone) then return public.api_error('INVALID_TIMEZONE'); end if;
 if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 20 then return public.api_error('INVALID_DISPLAY_NAME'); end if;
 select count(*) into n from public.space_members where space_id=s.id and status='active'; if n>=s.member_limit then return public.api_error('SPACE_FULL'); end if;
 if exists(select 1 from public.space_members m where m.space_id=s.id and m.status='active' and lower(m.display_name)=lower(btrim(p_display_name)) and (existing.id is null or m.id<>existing.id)) then return public.api_error('DISPLAY_NAME_TAKEN'); end if;
 insert into public.profiles(id,timezone) values(a,p_profile_timezone) on conflict(id) do update set timezone=excluded.timezone,updated_at=now();
 if existing.id is not null then
  mid:=existing.id;
  update public.space_members set display_name=btrim(p_display_name),role='member',status='active',disabled_at=null,disabled_by=null,end_reason=null where id=mid;
 else
  mid:=gen_random_uuid();
  insert into public.space_members(id,space_id,user_id,display_name,role) values(mid,s.id,a,btrim(p_display_name),'member');
 end if;
 result:=public.api_ok(jsonb_build_object('space',jsonb_build_object('id',s.id,'name',s.name,'timezone',s.timezone,'member_limit',s.member_limit,'daily_checkin_target_minutes',s.daily_checkin_target_minutes),
  'membership',jsonb_build_object('member_id',mid,'display_name',btrim(p_display_name),'role','member','status','active')));
 return public.store_command(a,p_idempotency_key,'join_space',h,null,result);
end $$;

create or replace function private.rpc_impl_get_my_membership() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=private.current_principal_id(); active_json jsonb; disabled_json jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 select jsonb_build_object('member_id',m.id,'space_id',m.space_id,'display_name',m.display_name,'role',m.role,'status',m.status,'joined_at',m.joined_at)
 into active_json from public.space_members m join public.spaces s on s.id=m.space_id where m.user_id=a and m.status='active' and s.lifecycle_status='active' order by m.joined_at limit 1;
 select jsonb_build_object('space_name',s.name,'display_name',m.display_name,'disabled_at',m.disabled_at,'end_reason',m.end_reason)
 into disabled_json from public.space_members m join public.spaces s on s.id=m.space_id where m.user_id=a and m.status='disabled' order by m.disabled_at desc limit 1;
 return public.api_ok(jsonb_build_object('membership',active_json,'latest_disabled_membership',disabled_json));
end $$;

revoke all on function private.rpc_impl_join_space(text,text,text,uuid),private.rpc_impl_get_my_membership() from public,anon,authenticated;
