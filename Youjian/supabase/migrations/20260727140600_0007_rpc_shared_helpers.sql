create function public.api_ok(p_data jsonb, p_request_id uuid default gen_random_uuid(), p_server_now timestamptz default now()) returns jsonb
language sql volatile set search_path = '' as $$
  select jsonb_build_object('ok', true, 'request_id', p_request_id, 'server_now', p_server_now, 'data', coalesce(p_data, '{}'::jsonb))
$$;
create function public.api_error(p_code text, p_details jsonb default '{}'::jsonb, p_authoritative_state jsonb default null,
  p_request_id uuid default gen_random_uuid(), p_server_now timestamptz default now()) returns jsonb
language sql volatile set search_path = '' as $$
  select jsonb_build_object('ok', false, 'request_id', p_request_id, 'server_now', p_server_now,
    'error', jsonb_build_object('code', p_code, 'details', coalesce(p_details, '{}'::jsonb)),
    'authoritative_state', p_authoritative_state)
$$;

create function public.invite_hash(p_token text) returns text
language sql immutable security definer set search_path = '' as $$
 select encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex')
$$;
create function public.new_invite_token() returns text
language sql volatile security definer set search_path = '' as $$
 select rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=')
$$;
create function public.derive_invite_token(p_actor uuid,p_key uuid,p_context text) returns text
language sql stable security definer set search_path='' as $$
 select rtrim(translate(encode(extensions.hmac(convert_to(p_actor::text||':'||p_key::text||':'||p_context,'UTF8'),s.secret,'sha256'),'base64'),'+/','-_'),'=')
 from private.app_secrets s where s.name='invite_hmac_key'
$$;
create function public.invite_url(p_token text) returns text
language sql stable security definer set search_path = '' as $$
 select coalesce(nullif(current_setting('app.settings.app_origin', true), ''), 'http://localhost:5173') || '/invite/' || p_token
$$;

create function public.command_cached(p_actor uuid, p_key uuid, p_type text, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.focus_commands%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text || ':' || p_key::text, 0));
  select * into c from public.focus_commands where actor_id=p_actor and idempotency_key=p_key;
  if not found then return null; end if;
  if c.command_type <> p_type or c.request_hash <> p_hash then
    return public.api_error('IDEMPOTENCY_KEY_REUSED');
  end if;
  return c.result;
end $$;
create function public.store_command(p_actor uuid, p_key uuid, p_type text, p_hash text, p_session uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.focus_commands(actor_id,idempotency_key,command_type,request_hash,session_id,result)
 values(p_actor,p_key,p_type,p_hash,p_session,p_result);
 return p_result;
end $$;

create function public.session_json(p_session_id uuid, p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object(
   'session_id', s.id, 'space_id', s.space_id, 'member_id', s.member_id, 'task_name', s.task_name,
   'category', s.category, 'status', s.status, 'started_at', s.started_at,
   'accumulated_focus_seconds', s.accumulated_focus_seconds,
   'active_segment_started_at', s.active_segment_started_at, 'paused_at', s.paused_at,
   'auto_settle_at', case when s.status='focusing' then s.active_segment_started_at + make_interval(secs => 21600-s.accumulated_focus_seconds)
                          when s.status='paused' then s.paused_at + interval '15 minutes' end,
   'completed_at', s.completed_at, 'completion_reason', s.completion_reason,
   'credited_focus_seconds', case when s.status in ('completed','discarded') then s.accumulated_focus_seconds end,
   'counts_toward_stats', case when s.status='completed' then true when s.status='discarded' then false end,
   'connection', jsonb_build_object('status', case when s.status='focusing' and p_at-s.last_seen_at > interval '120 seconds' then 'unconfirmed' else 'connected' end,
      'last_seen_at', s.last_seen_at, 'unconfirmed_connection_seconds', s.unconfirmed_connection_seconds)
 ) from public.focus_sessions s where s.id=p_session_id
$$;

create function public.record_focus_event(p_session_id uuid, p_actor_id uuid, p_event public.focus_event_type,
 p_at timestamptz default now(), p_metadata jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = '' as $$
 insert into public.focus_events(session_id,actor_id,event_type,occurred_at,metadata) values(p_session_id,p_actor_id,p_event,p_at,p_metadata)
$$;

create function public.finish_focus_session(p_session_id uuid, p_at timestamptz, p_reason public.completion_reason) returns uuid
language plpgsql security definer set search_path = '' as $$
declare s public.focus_sessions%rowtype; v_end timestamptz; v_delta int; v_total int; v_status public.focus_status;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in ('completed','discarded') then return p_session_id; end if;
 v_end := case when s.status='paused' then s.paused_at else p_at end;
 if s.status='focusing' then
   v_end := least(v_end, s.active_segment_started_at + make_interval(secs => 21600-s.accumulated_focus_seconds));
   v_delta := greatest(0, floor(extract(epoch from (v_end-s.active_segment_started_at)))::int);
   update public.focus_segments set ended_at=v_end where session_id=s.id and ended_at is null;
 else v_delta := 0; end if;
 v_total := least(21600, s.accumulated_focus_seconds+v_delta);
 v_status := case when v_total < 300 then 'discarded'::public.focus_status else 'completed'::public.focus_status end;
 update public.focus_connection_intervals set ended_at=v_end where session_id=s.id and ended_at is null;
 update public.focus_sessions set status=v_status, accumulated_focus_seconds=v_total, active_segment_started_at=null,
   paused_at=null, completed_at=v_end, completion_reason=p_reason, version=version+1 where id=s.id;
 perform public.record_focus_event(s.id, null, 'completed', v_end, jsonb_build_object('reason',p_reason));
 return s.id;
end $$;

create function public.settle_session(p_session_id uuid, p_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path = '' as $$
declare s public.focus_sessions%rowtype; v_cutoff timestamptz; v_closed_seconds numeric:=0;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in ('completed','discarded') then return p_session_id; end if;
 if s.status='paused' and p_at >= s.paused_at+interval '15 minutes' then
   return public.finish_focus_session(s.id,s.paused_at,'pause_timeout');
 elsif s.status='focusing' then
   select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds from public.focus_segments where session_id=s.id and ended_at is not null;
   v_cutoff := s.active_segment_started_at + make_interval(secs => (21600-v_closed_seconds)::double precision);
   if p_at >= v_cutoff then return public.finish_focus_session(s.id,v_cutoff,'focus_limit'); end if;
 end if;
 return p_session_id;
end $$;

create function public.get_my_membership() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); active_json jsonb; disabled_json jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 select jsonb_build_object('member_id',m.id,'space_id',m.space_id,'display_name',m.display_name,'role',m.role,'status',m.status,'joined_at',m.joined_at)
 into active_json from public.space_members m where m.user_id=a and m.status='active' order by m.joined_at limit 1;
 select jsonb_build_object('space_name',s.name,'display_name',m.display_name,'disabled_at',m.disabled_at)
 into disabled_json from public.space_members m join public.spaces s on s.id=m.space_id where m.user_id=a and m.status='disabled' order by m.disabled_at desc limit 1;
 return public.api_ok(jsonb_build_object('membership',active_json,'latest_disabled_membership',disabled_json));
end $$;

create function public.get_invite_preview(p_invite_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s public.spaces%rowtype; owner_name text; n int;
begin
 if p_invite_token is null or length(p_invite_token) < 40 then return public.api_error('INVITE_INVALID'); end if;
 select * into s from public.spaces where invite_token_hash=public.invite_hash(p_invite_token);
 if not found then return public.api_error('INVITE_INVALID'); end if;
 select count(*), max(display_name) filter(where role='owner') into n,owner_name from public.space_members where space_id=s.id and status='active';
 return public.api_ok(jsonb_build_object('status',case when n>=s.member_limit then 'full' else 'valid' end,'space_name',s.name,
  'owner_display_name',owner_name,'active_member_count',n,'member_limit',s.member_limit,'space_timezone',s.timezone));
end $$;

create function public.create_space(p_display_name text,p_space_name text,p_space_timezone text,p_profile_timezone text,
 p_member_limit smallint,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text; cached jsonb; token text; sid uuid; mid uuid; result jsonb; replay_result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_display_name,'')||'|'||coalesce(p_space_name,'')||'|'||coalesce(p_space_timezone,'')||'|'||coalesce(p_profile_timezone,'')||'|'||coalesce(p_member_limit::text,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'create_space',h);
 if cached is not null then
  if cached->>'ok'='false' then return cached; end if;
  token:=public.derive_invite_token(a,p_idempotency_key,'create_space');
  return jsonb_set(cached,'{data,invite}',jsonb_build_object('invite_url',public.invite_url(token)),true);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a::text,0));
 if exists(select 1 from public.space_members where user_id=a and status='active') then return public.api_error('ALREADY_IN_ANOTHER_SPACE'); end if;
 if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 20 then return public.api_error('INVALID_DISPLAY_NAME'); end if;
 if p_space_name is null or char_length(btrim(p_space_name)) not between 1 and 30 then return public.api_error('INVALID_SPACE_NAME'); end if;
 if not public.validate_iana_timezone(p_space_timezone) or not public.validate_iana_timezone(p_profile_timezone) then return public.api_error('INVALID_TIMEZONE'); end if;
 if p_member_limit not between 2 and 12 then return public.api_error('INVALID_MEMBER_LIMIT'); end if;
 token:=public.derive_invite_token(a,p_idempotency_key,'create_space'); sid:=gen_random_uuid(); mid:=gen_random_uuid();
 insert into public.profiles(id,timezone) values(a,p_profile_timezone) on conflict(id) do update set timezone=excluded.timezone,updated_at=now();
 insert into public.spaces(id,name,owner_id,timezone,member_limit,invite_token_hash) values(sid,btrim(p_space_name),a,p_space_timezone,p_member_limit,public.invite_hash(token));
 insert into public.space_members(id,space_id,user_id,display_name,role) values(mid,sid,a,btrim(p_display_name),'owner');
 result:=public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sid,'name',btrim(p_space_name),'timezone',p_space_timezone,'member_limit',p_member_limit,'daily_checkin_target_minutes',60),
  'membership',jsonb_build_object('member_id',mid,'display_name',btrim(p_display_name),'role','owner','status','active'),
  'invite',jsonb_build_object('invite_url',public.invite_url(token))));
 replay_result:=result#-'{data,invite}';
 perform public.store_command(a,p_idempotency_key,'create_space',h,null,replay_result);
 return result;
end $$;

create function public.join_space(p_invite_token text,p_display_name text,p_profile_timezone text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text; cached jsonb; s public.spaces%rowtype; existing public.space_members%rowtype; mid uuid; n int; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_invite_token,'')||'|'||coalesce(p_display_name,'')||'|'||coalesce(p_profile_timezone,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'join_space',h); if cached is not null then return cached; end if;
 select * into s from public.spaces where invite_token_hash=public.invite_hash(p_invite_token) for update;
 if not found then return public.api_error('INVITE_INVALID'); end if;
 select * into existing from public.space_members where user_id=a and space_id=s.id;
 if found then
  if existing.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
  return public.api_error('ALREADY_IN_SPACE','{}',jsonb_build_object('membership',jsonb_build_object('member_id',existing.id,'space_id',s.id,'display_name',existing.display_name,'role',existing.role,'status',existing.status)));
 end if;
 if exists(select 1 from public.space_members where user_id=a and status='active') then return public.api_error('ALREADY_IN_ANOTHER_SPACE'); end if;
 if not public.validate_iana_timezone(p_profile_timezone) then return public.api_error('INVALID_TIMEZONE'); end if;
 if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 20 then return public.api_error('INVALID_DISPLAY_NAME'); end if;
 select count(*) into n from public.space_members where space_id=s.id and status='active'; if n>=s.member_limit then return public.api_error('SPACE_FULL'); end if;
 if exists(select 1 from public.space_members where space_id=s.id and status='active' and lower(display_name)=lower(btrim(p_display_name))) then return public.api_error('DISPLAY_NAME_TAKEN'); end if;
 mid:=gen_random_uuid(); insert into public.profiles(id,timezone) values(a,p_profile_timezone) on conflict(id) do update set timezone=excluded.timezone,updated_at=now();
 insert into public.space_members(id,space_id,user_id,display_name,role) values(mid,s.id,a,btrim(p_display_name),'member');
 result:=public.api_ok(jsonb_build_object('space',jsonb_build_object('id',s.id,'name',s.name,'timezone',s.timezone,'member_limit',s.member_limit,'daily_checkin_target_minutes',s.daily_checkin_target_minutes),
 'membership',jsonb_build_object('member_id',mid,'display_name',btrim(p_display_name),'role','member','status','active')));
 return public.store_command(a,p_idempotency_key,'join_space',h,null,result);
end $$;

create function public.rotate_invite(p_space_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text:=p_space_id::text; cached jsonb; token text; v int; result jsonb; replay_result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'rotate_invite',h);
 if cached is not null then
  if cached->>'ok'='false' then return cached; end if;
  v:=(cached#>>'{data,invite_version}')::int; token:=public.derive_invite_token(a,p_idempotency_key,'rotate_invite:'||p_space_id::text||':'||v);
  return jsonb_set(cached,'{data,invite_url}',to_jsonb(public.invite_url(token)),true);
 end if;
 if not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
 update public.spaces set invite_version=invite_version+1 where id=p_space_id returning invite_version into v;
 token:=public.derive_invite_token(a,p_idempotency_key,'rotate_invite:'||p_space_id::text||':'||v);
 update public.spaces set invite_token_hash=public.invite_hash(token) where id=p_space_id;
 result:=public.api_ok(jsonb_build_object('invite_url',public.invite_url(token),'invite_version',v));
 replay_result:=result#-'{data,invite_url}';
 perform public.store_command(a,p_idempotency_key,'rotate_invite',h,null,replay_result);
 return result;
end $$;

create function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; h text; cached jsonb; active_id uuid; sid uuid; result jsonb; cat public.focus_category;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 h:=encode(extensions.digest(convert_to(p_space_id::text||'|'||coalesce(p_task_name,'')||'|'||coalesce(p_category,''),'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'start_focus',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a::text,0));
 select * into m from public.space_members where user_id=a and space_id=p_space_id;
 if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if; if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 if p_task_name is null or char_length(btrim(p_task_name)) not between 1 and 80 then return public.api_error('INVALID_TASK_NAME'); end if;
 begin cat:=p_category::public.focus_category; exception when invalid_text_representation then return public.api_error('INVALID_CATEGORY'); end;
 select id into active_id from public.focus_sessions where user_id=a and status in ('focusing','paused') for update;
 if found then perform public.settle_session(active_id,now()); select id into active_id from public.focus_sessions where id=active_id and status in ('focusing','paused'); end if;
 if active_id is not null then return public.api_error('SESSION_ALREADY_ACTIVE','{}',public.session_json(active_id)); end if;
 sid:=gen_random_uuid(); insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
 values(sid,p_space_id,a,m.id,btrim(p_task_name),cat,'focusing',now(),now(),now());
 insert into public.focus_segments(session_id,started_at) values(sid,now()); perform public.record_focus_event(sid,a,'started');
 result:=public.api_ok(jsonb_build_object('session',public.session_json(sid)));
 return public.store_command(a,p_idempotency_key,'start_focus',h,sid,result);
end $$;

create function public.pause_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text:=p_session_id::text; cached jsonb; s public.focus_sessions%rowtype; delta int; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'pause_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found then return public.api_error('SESSION_NOT_FOUND'); end if; if s.user_id<>a then return public.api_error('SESSION_NOT_OWNED'); end if;
 if exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status in ('completed','discarded') then result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'pause_focus',h,s.id,result); end if;
 if s.status<>'focusing' then return public.api_error('SESSION_NOT_FOCUSING','{}',public.session_json(s.id)); end if;
 update public.focus_segments set ended_at=now() where session_id=s.id and ended_at is null;
 select coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::int into delta from public.focus_segments where session_id=s.id and ended_at is not null;
 update public.focus_sessions set status='paused',accumulated_focus_seconds=least(21600,delta),active_segment_started_at=null,paused_at=now(),version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,a,'paused'); result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
 return public.store_command(a,p_idempotency_key,'pause_focus',h,s.id,result);
end $$;

create function public.resume_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text:=p_session_id::text; cached jsonb; s public.focus_sessions%rowtype; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'resume_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found then return public.api_error('SESSION_NOT_FOUND'); end if; if s.user_id<>a then return public.api_error('SESSION_NOT_OWNED'); end if;
 if exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status in ('completed','discarded') then result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'resume_focus',h,s.id,result); end if;
 if s.status<>'paused' then return public.api_error('SESSION_NOT_PAUSED','{}',public.session_json(s.id)); end if;
 update public.focus_sessions set status='focusing',paused_at=null,active_segment_started_at=now(),last_seen_at=now(),version=version+1 where id=s.id;
 insert into public.focus_segments(session_id,started_at) values(s.id,now()); perform public.record_focus_event(s.id,a,'resumed');
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'resume_focus',h,s.id,result);
end $$;

create function public.end_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text:=p_session_id::text; cached jsonb; s public.focus_sessions%rowtype; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'end_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found then return public.api_error('SESSION_NOT_FOUND'); end if; if s.user_id<>a then return public.api_error('SESSION_NOT_OWNED'); end if;
 if s.status not in ('completed','discarded') and exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 if s.status not in ('completed','discarded') then perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id; end if;
 if s.status not in ('completed','discarded') then perform public.finish_focus_session(s.id,now(),'manual_end'); end if;
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'end_focus',h,s.id,result);
end $$;

create function public.heartbeat_focus(p_session_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); s public.focus_sessions%rowtype; reconnect boolean:=false;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found then return public.api_error('SESSION_NOT_FOUND'); end if; if s.user_id<>a then return public.api_error('SESSION_NOT_OWNED'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status='focusing' then
   reconnect:=now()-s.last_seen_at>interval '120 seconds'; update public.focus_sessions set last_seen_at=now(),version=version+1 where id=s.id;
   if reconnect then update public.focus_connection_intervals set ended_at=now() where session_id=s.id and ended_at is null; perform public.record_focus_event(s.id,a,'reconnected'); end if;
 end if;
 return public.api_ok(jsonb_build_object('session',public.session_json(s.id),'connection_reconfirmed',reconnect));
end $$;

revoke all on function public.api_ok(jsonb,uuid,timestamptz), public.api_error(text,jsonb,jsonb,uuid,timestamptz), public.invite_hash(text),
 public.new_invite_token(), public.derive_invite_token(uuid,uuid,text), public.invite_url(text), public.command_cached(uuid,uuid,text,text), public.store_command(uuid,uuid,text,text,uuid,jsonb),
 public.session_json(uuid,timestamptz), public.record_focus_event(uuid,uuid,public.focus_event_type,timestamptz,jsonb),
 public.finish_focus_session(uuid,timestamptz,public.completion_reason), public.settle_session(uuid,timestamptz) from public;
grant execute on function public.get_invite_preview(text) to anon,authenticated;
grant execute on function public.get_my_membership(), public.create_space(text,text,text,text,smallint,uuid), public.join_space(text,text,text,uuid),
 public.rotate_invite(uuid,uuid), public.start_focus(uuid,text,text,uuid), public.pause_focus(uuid,uuid), public.resume_focus(uuid,uuid),
 public.end_focus(uuid,uuid), public.heartbeat_focus(uuid) to authenticated;
