alter table private.maintenance_runs add column duration_ms integer check(duration_ms>=0);
create table private.client_error_reports(
 id uuid primary key default gen_random_uuid(),actor_id uuid not null references auth.users(id),occurred_at timestamptz not null default now(),
 error_code text not null check(char_length(error_code) between 1 and 80),route text check(char_length(route)<=200),metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object')
);
revoke all on private.client_error_reports from public,anon,authenticated;

create or replace function public.create_space(p_display_name text,p_space_name text,p_space_timezone text,p_profile_timezone text,p_member_limit smallint,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text; cached jsonb; token text; sid uuid; mid uuid; result jsonb; replay_result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 if p_member_limit is null or p_member_limit not between 2 and 12 then return public.api_error('INVALID_MEMBER_LIMIT'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_display_name,'')||'|'||coalesce(p_space_name,'')||'|'||coalesce(p_space_timezone,'')||'|'||coalesce(p_profile_timezone,'')||'|'||p_member_limit::text,'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'create_space',h);
 if cached is not null then if cached->>'ok'='false' then return cached; end if; token:=public.derive_invite_token(a,p_idempotency_key,'create_space'); return jsonb_set(cached,'{data,invite}',jsonb_build_object('invite_url',public.invite_url(token)),true); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a::text,0));
 if exists(select 1 from public.space_members where user_id=a and status='active') then return public.api_error('ALREADY_IN_ANOTHER_SPACE'); end if;
 if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 20 then return public.api_error('INVALID_DISPLAY_NAME'); end if;
 if p_space_name is null or char_length(btrim(p_space_name)) not between 1 and 30 then return public.api_error('INVALID_SPACE_NAME'); end if;
 if not coalesce(public.validate_iana_timezone(p_space_timezone),false) or not coalesce(public.validate_iana_timezone(p_profile_timezone),false) then return public.api_error('INVALID_TIMEZONE'); end if;
 token:=public.derive_invite_token(a,p_idempotency_key,'create_space'); sid:=gen_random_uuid(); mid:=gen_random_uuid();
 insert into public.profiles(id,timezone) values(a,p_profile_timezone) on conflict(id) do update set timezone=excluded.timezone,updated_at=now();
 insert into public.spaces(id,name,owner_id,timezone,member_limit,invite_token_hash) values(sid,btrim(p_space_name),a,p_space_timezone,p_member_limit,public.invite_hash(token));
 insert into public.space_members(id,space_id,user_id,display_name,role) values(mid,sid,a,btrim(p_display_name),'owner');
 result:=public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sid,'name',btrim(p_space_name),'timezone',p_space_timezone,'member_limit',p_member_limit,'daily_checkin_target_minutes',60),
 'membership',jsonb_build_object('member_id',mid,'display_name',btrim(p_display_name),'role','owner','status','active'),'invite',jsonb_build_object('invite_url',public.invite_url(token))));
 replay_result:=result#-'{data,invite}'; perform public.store_command(a,p_idempotency_key,'create_space',h,null,replay_result); return result;
exception when check_violation or not_null_violation or invalid_text_representation then return public.api_error('INVALID_REQUEST');
end $$;

create function public.report_client_error(p_error_code text,p_route text default null,p_metadata jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); rid uuid;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_error_code is null or char_length(p_error_code) not between 1 and 80 or p_route is not null and char_length(p_route)>200 or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then return public.api_error('INVALID_ERROR_REPORT'); end if;
 if exists(select 1 from jsonb_object_keys(p_metadata) k where lower(k)~'(token|invite|task|nickname|display.?name|email|authorization)') then return public.api_error('SENSITIVE_METADATA_REJECTED'); end if;
 if octet_length(p_metadata::text)>4096 then return public.api_error('INVALID_ERROR_REPORT'); end if;
 insert into private.client_error_reports(actor_id,error_code,route,metadata) values(a,p_error_code,p_route,p_metadata) returning id into rid;
 return public.api_ok(jsonb_build_object('report_id',rid));
end $$;

create or replace function public.run_minute_maintenance() returns jsonb
language plpgsql security definer set search_path='' as $$
declare run_id bigint; output jsonb; t timestamptz:=now(); started_clock timestamptz:=clock_timestamp(); duration int;
begin
 insert into private.maintenance_runs(job_name,started_at,status) values('minute_maintenance',t,'running') returning id into run_id;
 begin
  output:=public.run_minute_maintenance_core(t); duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='succeeded',result=output where id=run_id; return output;
 exception when others then
  duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='failed',error_code=sqlstate,result=jsonb_build_object('message','maintenance failed') where id=run_id;
  return jsonb_build_object('ok',false,'error_code','MAINTENANCE_FAILED','run_id',run_id,'ran_at',t);
 end;
end $$;

revoke all on function public.report_client_error(text,text,jsonb) from public;
grant execute on function public.report_client_error(text,text,jsonb) to authenticated;
