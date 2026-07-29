create table private.invite_preview_rate_limits(
 token_hash text not null,client_hash text not null,window_start timestamptz not null,request_count integer not null check(request_count>0),
 primary key(token_hash,client_hash,window_start)
);
create table private.maintenance_runs(
 id bigint generated always as identity primary key,job_name text not null,started_at timestamptz not null,
 finished_at timestamptz,status text not null check(status in('running','succeeded','failed')),result jsonb,error_code text
);
revoke all on private.invite_preview_rate_limits,private.maintenance_runs from public,anon,authenticated;

create or replace function public.command_cached(p_actor uuid,p_key uuid,p_type text,p_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.focus_commands%rowtype;
begin
 if p_actor is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text||':'||p_key::text,0));
 select * into c from public.focus_commands where actor_id=p_actor and idempotency_key=p_key;
 if not found then return null; end if;
 if c.command_type<>p_type or c.request_hash<>p_hash then return public.api_error('IDEMPOTENCY_KEY_REUSED'); end if;
 return c.result;
end $$;

create or replace function public.get_invite_preview(p_invite_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.spaces%rowtype; owner_name text; n int; headers jsonb; fingerprint text; th text; ch text; ws timestamptz; hits int;
begin
 headers:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb);
 fingerprint:=coalesce(headers->>'cf-connecting-ip',split_part(coalesce(headers->>'x-forwarded-for','unknown'),',',1),'unknown')||'|'||coalesce(headers->>'x-client-fingerprint',headers->>'user-agent','unknown');
 th:=public.invite_hash(coalesce(p_invite_token,'')); ch:=encode(extensions.digest(convert_to(fingerprint,'UTF8'),'sha256'),'hex');
 ws:=to_timestamp(floor(extract(epoch from now())/300)*300);
 insert into private.invite_preview_rate_limits(token_hash,client_hash,window_start,request_count) values(th,ch,ws,1)
 on conflict(token_hash,client_hash,window_start) do update set request_count=private.invite_preview_rate_limits.request_count+1 returning request_count into hits;
 if hits>30 then return public.api_error('RATE_LIMITED',jsonb_build_object('retry_after_seconds',greatest(0,ceil(extract(epoch from(ws+interval '5 minutes'-now())))::int))); end if;
 if p_invite_token is null or length(p_invite_token)<40 then return public.api_error('INVITE_INVALID'); end if;
 select * into s from public.spaces where invite_token_hash=th; if not found then return public.api_error('INVITE_INVALID'); end if;
 select count(*),max(display_name) filter(where role='owner') into n,owner_name from public.space_members where space_id=s.id and status='active';
 return public.api_ok(jsonb_build_object('status',case when n>=s.member_limit then 'full' else 'valid' end,'space_name',s.name,'owner_display_name',owner_name,
  'active_member_count',n,'member_limit',s.member_limit,'space_timezone',s.timezone));
exception when invalid_text_representation then return public.api_error('INVITE_INVALID');
end $$;

create or replace function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); m public.space_members%rowtype; h text; cached jsonb; active_id uuid; sid uuid; result jsonb; cat public.focus_category;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 if p_category is null then return public.api_error('INVALID_CATEGORY'); end if;
 h:=encode(extensions.digest(convert_to(coalesce(p_space_id::text,'')||'|'||coalesce(p_task_name,'')||'|'||p_category,'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'start_focus',h); if cached is not null then return cached; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a::text,0));
 select * into m from public.space_members where user_id=a and space_id=p_space_id;
 if not found then return public.api_error('SPACE_ACCESS_DENIED'); end if; if m.status='disabled' then return public.api_error('MEMBER_DISABLED'); end if;
 if p_task_name is null or char_length(btrim(p_task_name)) not between 1 and 80 then return public.api_error('INVALID_TASK_NAME'); end if;
 begin cat:=p_category::public.focus_category; exception when invalid_text_representation then return public.api_error('INVALID_CATEGORY'); end;
 select id into active_id from public.focus_sessions where user_id=a and status in('focusing','paused') for update;
 if found then perform public.settle_session(active_id,now()); select id into active_id from public.focus_sessions where id=active_id and status in('focusing','paused'); end if;
 if active_id is not null then return public.api_error('SESSION_ALREADY_ACTIVE','{}',public.session_json(active_id)); end if;
 sid:=gen_random_uuid(); insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
 values(sid,p_space_id,a,m.id,btrim(p_task_name),cat,'focusing',now(),now(),now());
 insert into public.focus_segments(session_id,started_at) values(sid,now()); perform public.record_focus_event(sid,a,'started');
 result:=public.api_ok(jsonb_build_object('session',public.session_json(sid))); return public.store_command(a,p_idempotency_key,'start_focus',h,sid,result);
exception when check_violation or not_null_violation or invalid_text_representation then return public.api_error('INVALID_REQUEST');
end $$;

create or replace function public.pause_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_session_id::text,''); cached jsonb; s public.focus_sessions%rowtype; total int; result jsonb; u_start timestamptz; u_seconds int:=0;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'pause_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 if exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status in('completed','discarded') then result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'pause_focus',h,s.id,result); end if;
 if s.status<>'focusing' then return public.api_error('SESSION_NOT_FOCUSING','{}',public.session_json(s.id)); end if;
 update public.focus_segments set ended_at=now() where session_id=s.id and ended_at is null;
 select coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::int into total from public.focus_segments where session_id=s.id and ended_at is not null;
 select started_at into u_start from public.focus_connection_intervals where session_id=s.id and ended_at is null for update;
 if u_start is not null then u_seconds:=greatest(0,floor(extract(epoch from(now()-u_start)))::int); update public.focus_connection_intervals set ended_at=now() where session_id=s.id and ended_at is null; end if;
 update public.focus_sessions set status='paused',accumulated_focus_seconds=least(21600,total),active_segment_started_at=null,paused_at=now(),
  unconfirmed_connection_seconds=unconfirmed_connection_seconds+u_seconds,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,a,'paused'); result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
 return public.store_command(a,p_idempotency_key,'pause_focus',h,s.id,result);
end $$;

create or replace function public.resume_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_session_id::text,''); cached jsonb; s public.focus_sessions%rowtype; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'resume_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update; if not found or s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 if exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status in('completed','discarded') then result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'resume_focus',h,s.id,result); end if;
 if s.status<>'paused' then return public.api_error('SESSION_NOT_PAUSED','{}',public.session_json(s.id)); end if;
 update public.focus_sessions set status='focusing',paused_at=null,active_segment_started_at=now(),last_seen_at=now(),version=version+1 where id=s.id;
 insert into public.focus_segments(session_id,started_at) values(s.id,now()); perform public.record_focus_event(s.id,a,'resumed');
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'resume_focus',h,s.id,result);
end $$;

create or replace function public.end_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_session_id::text,''); cached jsonb; s public.focus_sessions%rowtype; result jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if; if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'end_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update; if not found or s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 if s.status not in('completed','discarded') and exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 if s.status not in('completed','discarded') then perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id; end if;
 if s.status not in('completed','discarded') then perform public.finish_focus_session(s.id,now(),'manual_end'); end if;
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id))); return public.store_command(a,p_idempotency_key,'end_focus',h,s.id,result);
end $$;

create or replace function public.heartbeat_focus(p_session_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); s public.focus_sessions%rowtype; reconnect boolean:=false; interval_start timestamptz; added int:=0;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 select * into s from public.focus_sessions where id=p_session_id for update; if not found or s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status='focusing' then
  reconnect:=now()-s.last_seen_at>interval '120 seconds';
  if reconnect then
   select started_at into interval_start from public.focus_connection_intervals where session_id=s.id and ended_at is null for update;
   if interval_start is null then interval_start:=s.last_seen_at+interval '120 seconds'; insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(s.id,interval_start,s.last_seen_at); end if;
   added:=greatest(0,floor(extract(epoch from(now()-interval_start)))::int); update public.focus_connection_intervals set ended_at=now() where session_id=s.id and ended_at is null; perform public.record_focus_event(s.id,a,'reconnected');
  end if;
  update public.focus_sessions set last_seen_at=now(),unconfirmed_connection_seconds=unconfirmed_connection_seconds+added,version=version+1 where id=s.id;
 end if;
 select * into s from public.focus_sessions where id=s.id;
 return public.api_ok(jsonb_build_object('session',public.session_json(s.id),'connection_reconfirmed',reconnect));
end $$;

revoke all on function public.command_cached(uuid,uuid,text,text) from public;
