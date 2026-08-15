-- Policy v2 changes the hard focus cap for every session started after this
-- migration to four hours. Existing sessions and historical rows retain the
-- six-hour cap that governed them when they started.

alter table public.focus_sessions add column max_focus_seconds integer;
alter table public.focus_sessions disable trigger settled_focus_sessions_are_immutable;
update public.focus_sessions set max_focus_seconds=21600 where max_focus_seconds is null;
alter table public.focus_sessions enable trigger settled_focus_sessions_are_immutable;
alter table public.focus_sessions
  alter column max_focus_seconds set default 14400,
  alter column max_focus_seconds set not null,
  add constraint focus_sessions_max_focus_seconds_valid
    check (max_focus_seconds in (14400,21600));

create or replace function public.session_json(p_session_id uuid,p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
   'session_id',s.id,'space_id',s.space_id,'member_id',s.member_id,'task_name',s.task_name,
   'category',s.category,'task_history',private.focus_task_history_json(s.id),
   'status',s.status,'started_at',s.started_at,'timezone_snapshot',s.timezone_snapshot,
   'accumulated_focus_seconds',s.accumulated_focus_seconds,'max_focus_seconds',s.max_focus_seconds,
   'active_segment_started_at',s.active_segment_started_at,'paused_at',s.paused_at,
   'auto_settle_at',case
     when s.health_check_state='pending' and s.status='focusing' then s.health_check_deadline_at
     when s.status='focusing' then s.active_segment_started_at+make_interval(secs=>s.max_focus_seconds-s.accumulated_focus_seconds)
     when s.status='paused' then s.paused_at+interval '15 minutes' end,
   'health_check',jsonb_build_object(
     'policy_version',s.health_check_policy_version,
     'state',s.health_check_state,
     'triggered_at',s.health_check_triggered_at,
     'deadline_at',s.health_check_deadline_at,
     'result_seen',exists(select 1 from private.health_check_result_reads r where r.session_id=s.id and r.user_id=private.current_principal_id())
   ),
   'completed_at',s.completed_at,'completion_reason',s.completion_reason,
   'credited_focus_seconds',case when s.status in('completed','discarded') then s.accumulated_focus_seconds end,
   'counts_toward_stats',case when s.status='completed' then true when s.status='discarded' then false end,
   'connection',jsonb_build_object('status',case when s.status='focusing' and p_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,
      'last_seen_at',s.last_seen_at,'unconfirmed_connection_seconds',s.unconfirmed_connection_seconds)
 ) from public.focus_sessions s where s.id=p_session_id
$$;
revoke all on function public.session_json(uuid,timestamptz) from public,anon,authenticated;

create or replace function public.finish_focus_session(p_session_id uuid,p_at timestamptz,p_reason public.completion_reason) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; v_end timestamptz; v_total int; v_status public.focus_status; v_uncertain int:=0; v_closed_seconds numeric:=0;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in('completed','discarded') then return p_session_id; end if;
 v_end:=case when s.status='paused' then s.paused_at else p_at end;
 select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds from public.focus_segments where session_id=s.id and ended_at is not null;
 if s.status='focusing' then
  v_end:=least(v_end,s.active_segment_started_at+make_interval(secs=>(s.max_focus_seconds-v_closed_seconds)::double precision));
  update public.focus_segments set ended_at=v_end where session_id=s.id and ended_at is null;
 end if;
 select coalesce(floor(sum(extract(epoch from(v_end-started_at))) filter(where started_at<v_end)),0)::int into v_uncertain
 from public.focus_connection_intervals where session_id=s.id and ended_at is null;
 update public.focus_connection_intervals set ended_at=v_end where session_id=s.id and ended_at is null and started_at<v_end;
 delete from public.focus_connection_intervals where session_id=s.id and ended_at is null and started_at>=v_end;
 select least(s.max_focus_seconds,coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::int) into v_total from public.focus_segments where session_id=s.id and ended_at is not null;
 v_status:=case when v_total<300 then 'discarded'::public.focus_status else 'completed'::public.focus_status end;
 update public.focus_sessions set status=v_status,accumulated_focus_seconds=v_total,active_segment_started_at=null,paused_at=null,completed_at=v_end,
  completion_reason=p_reason,unconfirmed_connection_seconds=unconfirmed_connection_seconds+v_uncertain,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,private.current_principal_id(),'completed',v_end,jsonb_build_object('reason',p_reason));
 return s.id;
end $$;
revoke all on function public.finish_focus_session(uuid,timestamptz,public.completion_reason) from public,anon,authenticated;

create or replace function private.rpc_impl_pause_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); h text:=coalesce(p_session_id::text,''); cached jsonb; s public.focus_sessions%rowtype; total int; result jsonb; u_start timestamptz; u_seconds int:=0;
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
 update public.focus_sessions set status='paused',accumulated_focus_seconds=least(s.max_focus_seconds,total),active_segment_started_at=null,paused_at=now(),
  unconfirmed_connection_seconds=unconfirmed_connection_seconds+u_seconds,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,a,'paused'); result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
 return public.store_command(a,p_idempotency_key,'pause_focus',h,s.id,result);
end $$;
revoke all on function private.rpc_impl_pause_focus(uuid,uuid) from public,anon,authenticated;

create or replace function public.settle_session(p_session_id uuid,p_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; v_cutoff timestamptz; v_closed_seconds numeric:=0; v_deadline timestamptz;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in('completed','discarded') then return p_session_id; end if;
 if s.health_check_state in('waiting','pending') and not private.focus_health_check_enabled() then
   update public.focus_sessions set health_check_state='cancelled',health_check_deadline_at=null,version=version+1 where id=s.id; select * into s from public.focus_sessions where id=s.id;
 end if;
 if s.health_check_state='pending' and s.status='paused' and p_at>=s.paused_at+interval '5 minutes' then
   update public.focus_sessions set health_check_state='satisfied_by_pause',health_check_deadline_at=null,version=version+1 where id=s.id;
   perform public.record_focus_event(s.id,null,'health_check_satisfied_by_pause',s.paused_at+interval '5 minutes'); select * into s from public.focus_sessions where id=s.id;
 end if;
 if s.status='paused' and p_at>=s.paused_at+interval '15 minutes' then return public.finish_focus_session(s.id,s.paused_at,'pause_timeout'); end if;
 if s.status='focusing' then
   select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds from public.focus_segments where session_id=s.id and ended_at is not null;
   if s.health_check_state='waiting' then
     v_cutoff:=s.active_segment_started_at+make_interval(secs=>(7200-v_closed_seconds)::double precision);
     if p_at>=v_cutoff then
       if s.health_check_qualifying_pause_focus_seconds is not null and 7200-s.health_check_qualifying_pause_focus_seconds<=1800 then
         update public.focus_sessions set health_check_state='satisfied_by_pause',health_check_deadline_at=null,version=version+1 where id=s.id;
         perform public.record_focus_event(s.id,null,'health_check_satisfied_by_pause',v_cutoff);
       else
         update public.focus_sessions set health_check_state='pending',health_check_triggered_at=v_cutoff,health_check_deadline_at=v_cutoff+interval '1 minute',version=version+1 where id=s.id;
         perform public.record_focus_event(s.id,null,'health_check_triggered',v_cutoff);
       end if;
       select * into s from public.focus_sessions where id=s.id;
     end if;
   end if;
   if s.health_check_state='pending' and s.health_check_deadline_at is not null and p_at>=s.health_check_deadline_at then
     v_deadline:=s.health_check_deadline_at; return public.finish_focus_session(s.id,v_deadline,'health_check_timeout');
   end if;
   v_cutoff:=s.active_segment_started_at+make_interval(secs=>(s.max_focus_seconds-v_closed_seconds)::double precision);
   if p_at>=v_cutoff then return public.finish_focus_session(s.id,v_cutoff,'focus_limit'); end if;
 end if;
 return p_session_id;
end $$;
revoke all on function public.settle_session(uuid,timestamptz) from public,anon,authenticated;

create or replace function public.run_minute_maintenance_core(p_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; settled int:=0; uncertain int:=0; goals jsonb;
begin
 for r in
   select id from public.focus_sessions
   where status in('focusing','paused') and (
     (status='paused' and paused_at+interval '15 minutes'<=p_at) or
     (status='focusing' and active_segment_started_at+make_interval(secs=>max_focus_seconds-accumulated_focus_seconds)<=p_at) or
     (health_check_state='waiting' and status='focusing' and active_segment_started_at+make_interval(secs=>7200-accumulated_focus_seconds)<=p_at) or
     (health_check_state='pending' and ((status='focusing' and health_check_deadline_at<=p_at) or (status='paused' and paused_at+interval '5 minutes'<=p_at))) or
     (health_check_state='pending' and not private.focus_health_check_enabled())
   ) order by started_at limit 100 for update skip locked
 loop perform public.settle_session(r.id,p_at); settled:=settled+1; end loop;
 for r in select id,last_seen_at from public.focus_sessions where status='focusing' and last_seen_at+interval '120 seconds'<=p_at order by last_seen_at limit 100 for update skip locked loop
  if not exists(select 1 from public.focus_connection_intervals where session_id=r.id and ended_at is null) then
   insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(r.id,r.last_seen_at+interval '120 seconds',r.last_seen_at);
   perform public.record_focus_event(r.id,null,'connection_unconfirmed',r.last_seen_at+interval '120 seconds');
   update public.focus_sessions set version=version+1 where id=r.id; uncertain:=uncertain+1;
  end if;
 end loop;
 goals:=public.run_goal_maintenance(p_at); delete from public.focus_commands where created_at<p_at-interval '30 days';
 return jsonb_build_object('settled_sessions',settled,'new_unconfirmed_intervals',uncertain,'goal_maintenance',goals,'ran_at',p_at);
end $$;
revoke all on function public.run_minute_maintenance_core(timestamptz) from public,anon,authenticated;

-- Old policy clients can learn that an update is required, but cannot silently
-- acknowledge v2 after rendering the v1 six-hour copy.
create or replace function public.acknowledge_focus_health_policy(p_policy_version integer) returns jsonb
language sql security definer set search_path='' as $$ select public.api_error('CLIENT_UPDATE_REQUIRED') $$;
revoke all on function public.acknowledge_focus_health_policy(integer) from public,anon;
grant execute on function public.acknowledge_focus_health_policy(integer) to authenticated;

create function public.acknowledge_focus_health_policy(p_policy_version integer,p_policy_contract text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_policy_version<>2 or p_policy_contract<>'max_focus_seconds=14400' then return public.api_error('CLIENT_UPDATE_REQUIRED'); end if;
 update public.profiles set health_check_policy_version=greatest(health_check_policy_version,p_policy_version),updated_at=now() where id=a;
 if not found then return public.api_error('PROFILE_NOT_FOUND'); end if;
 return public.api_ok(jsonb_build_object('acknowledged_version',p_policy_version));
end $$;
revoke all on function public.acknowledge_focus_health_policy(integer,text) from public,anon;
grant execute on function public.acknowledge_focus_health_policy(integer,text) to authenticated;

create or replace function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_timezone text,p_health_check_policy_version integer,p_idempotency_key uuid) returns jsonb
language sql security definer set search_path='' as $$ select public.api_error('CLIENT_UPDATE_REQUIRED') $$;
revoke all on function public.start_focus(uuid,text,text,text,integer,uuid) from public,anon;
grant execute on function public.start_focus(uuid,text,text,text,integer,uuid) to authenticated;

create function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_timezone text,p_health_check_policy_version integer,p_policy_contract text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); result jsonb; sid uuid; enabled boolean:=private.focus_health_check_enabled();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_health_check_policy_version<>2 or p_policy_contract<>'max_focus_seconds=14400' then return public.api_error('CLIENT_UPDATE_REQUIRED'); end if;
 if enabled and not exists(select 1 from public.profiles where id=a and health_check_policy_version>=2) then return public.api_error('HEALTH_POLICY_ACK_REQUIRED'); end if;
 result:=public.start_focus(p_space_id,p_task_name,p_category,p_timezone,p_idempotency_key);
 if result->>'ok'<>'true' then return result; end if;
 sid:=(result#>>'{data,session,session_id}')::uuid;
 update public.focus_sessions set health_check_policy_version=case when enabled then 2 else null end,
   health_check_state=case when enabled then 'waiting' else 'not_applicable' end,version=version+1
 where id=sid and user_id=a and status in('focusing','paused');
 return jsonb_set(result,'{data,session}',public.session_json(sid),true);
end $$;
revoke all on function public.start_focus(uuid,text,text,text,integer,text,uuid) from public,anon;
grant execute on function public.start_focus(uuid,text,text,text,integer,text,uuid) to authenticated;

create or replace function public.get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; a uuid:=private.current_principal_id(); acknowledged integer:=0;
begin
 result:=private.rpc_impl_get_home_snapshot(p_space_id);
 if result->>'ok'='true' then
   select health_check_policy_version into acknowledged from public.profiles where id=a;
   result:=jsonb_set(result,'{data,health_check_policy}',jsonb_build_object(
     'current_version',2,'acknowledged_version',coalesce(acknowledged,0),'enabled',private.focus_health_check_enabled()),true);
   result:=jsonb_set(result,'{data,unseen_health_check_result}',coalesce((
     select public.session_json(s.id) from public.focus_sessions s
     where s.user_id=a and s.completion_reason in('health_check_accepted','health_check_timeout')
       and not exists(select 1 from private.health_check_result_reads r where r.user_id=a and r.session_id=s.id)
     order by s.completed_at desc limit 1
   ),'null'::jsonb),true);
 end if;
 return result;
exception when others then return private.rpc_internal_error_envelope('get_home_snapshot',sqlstate);
end $$;
revoke all on function public.get_home_snapshot(uuid) from public,anon;
grant execute on function public.get_home_snapshot(uuid) to authenticated;
