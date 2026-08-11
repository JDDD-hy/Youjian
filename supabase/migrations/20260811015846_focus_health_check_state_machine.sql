-- Server-authoritative, one-shot focus health check. Legacy start_focus clients
-- keep the pre-policy behavior; policy-aware clients use the new overload.

alter table public.profiles
  add column health_check_policy_version smallint not null default 0
  check (health_check_policy_version >= 0);

alter table public.focus_sessions
  add column health_check_policy_version smallint,
  add column health_check_state text not null default 'not_applicable'
    check (health_check_state in ('not_applicable','waiting','pending','continued','satisfied_by_pause','cancelled')),
  add column health_check_triggered_at timestamptz,
  add column health_check_deadline_at timestamptz,
  add column health_check_qualifying_pause_focus_seconds integer
    check (health_check_qualifying_pause_focus_seconds between 0 and 21600),
  add constraint focus_health_check_consistency check (
    (health_check_state='pending' and health_check_triggered_at is not null) or
    (health_check_state<>'pending' and health_check_deadline_at is null)
  );

create index focus_sessions_health_check_due
on public.focus_sessions(health_check_deadline_at)
where status in ('focusing','paused') and health_check_state='pending';

create table private.feature_flags(
  name text primary key,
  enabled boolean not null,
  updated_at timestamptz not null default now()
);
insert into private.feature_flags(name,enabled) values('focus_health_check_v1',true);
revoke all on private.feature_flags from public,anon,authenticated;

create table private.health_check_result_reads(
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null references public.focus_sessions(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key(user_id,session_id)
);
revoke all on private.health_check_result_reads from public,anon,authenticated;

create function private.focus_health_check_enabled() returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((select enabled from private.feature_flags where name='focus_health_check_v1'),false)
$$;
revoke all on function private.focus_health_check_enabled() from public,anon,authenticated;

create or replace function public.session_json(p_session_id uuid,p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
   'session_id',s.id,'space_id',s.space_id,'member_id',s.member_id,'task_name',s.task_name,
   'category',s.category,'task_history',private.focus_task_history_json(s.id),
   'status',s.status,'started_at',s.started_at,'timezone_snapshot',s.timezone_snapshot,
   'accumulated_focus_seconds',s.accumulated_focus_seconds,
   'active_segment_started_at',s.active_segment_started_at,'paused_at',s.paused_at,
   'auto_settle_at',case
     when s.health_check_state='pending' and s.status='focusing' then s.health_check_deadline_at
     when s.status='focusing' then s.active_segment_started_at+make_interval(secs=>21600-s.accumulated_focus_seconds)
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

create function private.apply_focus_health_pause_transition() returns trigger
language plpgsql security definer set search_path='' as $$
declare pause_seconds numeric;
begin
 if old.status='focusing' and new.status='paused' and old.health_check_state='pending' then
   new.health_check_deadline_at:=null;
 elsif old.status='paused' and new.status='focusing' then
   pause_seconds:=extract(epoch from(now()-old.paused_at));
   if old.health_check_state='pending' then
     if pause_seconds>=300 then
       new.health_check_state:='satisfied_by_pause';
       new.health_check_deadline_at:=null;
       perform public.record_focus_event(old.id,private.current_principal_id(),'health_check_satisfied_by_pause',now());
     else
       new.health_check_deadline_at:=now()+interval '1 minute';
     end if;
   elsif old.health_check_state='waiting' and pause_seconds>=300 then
     new.health_check_qualifying_pause_focus_seconds:=new.accumulated_focus_seconds;
   end if;
 end if;
 return new;
end $$;
revoke all on function private.apply_focus_health_pause_transition() from public,anon,authenticated;
create trigger apply_focus_health_pause_transition
before update of status on public.focus_sessions
for each row execute function private.apply_focus_health_pause_transition();

create or replace function public.settle_session(p_session_id uuid,p_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; v_cutoff timestamptz; v_closed_seconds numeric:=0; v_deadline timestamptz;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in('completed','discarded') then return p_session_id; end if;

 if s.health_check_state in('waiting','pending') and not private.focus_health_check_enabled() then
   update public.focus_sessions set health_check_state='cancelled',health_check_deadline_at=null,version=version+1 where id=s.id;
   select * into s from public.focus_sessions where id=s.id;
 end if;

 if s.health_check_state='pending' and s.status='paused' and p_at>=s.paused_at+interval '5 minutes' then
   update public.focus_sessions set health_check_state='satisfied_by_pause',health_check_deadline_at=null,version=version+1 where id=s.id;
   perform public.record_focus_event(s.id,null,'health_check_satisfied_by_pause',s.paused_at+interval '5 minutes');
   select * into s from public.focus_sessions where id=s.id;
 end if;

 if s.status='paused' and p_at>=s.paused_at+interval '15 minutes' then
   return public.finish_focus_session(s.id,s.paused_at,'pause_timeout');
 end if;

 if s.status='focusing' then
   select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds
   from public.focus_segments where session_id=s.id and ended_at is not null;

   if s.health_check_state='waiting' then
     v_cutoff:=s.active_segment_started_at+make_interval(secs=>(7200-v_closed_seconds)::double precision);
     if p_at>=v_cutoff then
       if s.health_check_qualifying_pause_focus_seconds is not null
          and 7200-s.health_check_qualifying_pause_focus_seconds<=1800 then
         update public.focus_sessions set health_check_state='satisfied_by_pause',health_check_deadline_at=null,version=version+1 where id=s.id;
         perform public.record_focus_event(s.id,null,'health_check_satisfied_by_pause',v_cutoff);
       else
         update public.focus_sessions set health_check_state='pending',health_check_triggered_at=v_cutoff,
           health_check_deadline_at=v_cutoff+interval '1 minute',version=version+1 where id=s.id;
         perform public.record_focus_event(s.id,null,'health_check_triggered',v_cutoff);
       end if;
       select * into s from public.focus_sessions where id=s.id;
     end if;
   end if;

   if s.health_check_state='pending' and s.health_check_deadline_at is not null and p_at>=s.health_check_deadline_at then
     v_deadline:=s.health_check_deadline_at;
     return public.finish_focus_session(s.id,v_deadline,'health_check_timeout');
   end if;

   v_cutoff:=s.active_segment_started_at+make_interval(secs=>(21600-v_closed_seconds)::double precision);
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
     (status='focusing' and active_segment_started_at+make_interval(secs=>21600-accumulated_focus_seconds)<=p_at) or
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

create function public.acknowledge_focus_health_policy(p_policy_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_policy_version<>1 then return public.api_error('INVALID_POLICY_VERSION'); end if;
 update public.profiles set health_check_policy_version=greatest(health_check_policy_version,p_policy_version),updated_at=now() where id=a;
 if not found then return public.api_error('PROFILE_NOT_FOUND'); end if;
 return public.api_ok(jsonb_build_object('acknowledged_version',p_policy_version));
end $$;
revoke all on function public.acknowledge_focus_health_policy(integer) from public,anon;
grant execute on function public.acknowledge_focus_health_policy(integer) to authenticated;

create function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_timezone text,p_health_check_policy_version integer,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); result jsonb; sid uuid; enabled boolean:=private.focus_health_check_enabled();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if enabled and (p_health_check_policy_version<>1 or not exists(select 1 from public.profiles where id=a and health_check_policy_version>=1)) then
   return public.api_error('HEALTH_POLICY_ACK_REQUIRED');
 end if;
 result:=public.start_focus(p_space_id,p_task_name,p_category,p_timezone,p_idempotency_key);
 if result->>'ok'<>'true' then return result; end if;
 sid:=(result#>>'{data,session,session_id}')::uuid;
 if enabled then
   update public.focus_sessions set health_check_policy_version=1,health_check_state='waiting',version=version+1
   where id=sid and user_id=a and status in('focusing','paused');
 end if;
 return jsonb_set(result,'{data,session}',public.session_json(sid),true);
end $$;
revoke all on function public.start_focus(uuid,text,text,text,integer,uuid) from public,anon;
grant execute on function public.start_focus(uuid,text,text,text,integer,uuid) to authenticated;

create function public.respond_focus_health_check(p_session_id uuid,p_choice text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); s public.focus_sessions%rowtype; h text; cached jsonb; result jsonb; action_at timestamptz:=now();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 if p_choice not in('end','continue') then return public.api_error('INVALID_HEALTH_CHECK_CHOICE'); end if;
 h:=coalesce(p_session_id::text,'')||'|'||p_choice;
 cached:=public.command_cached(a,p_idempotency_key,'respond_focus_health_check',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 perform public.settle_session(s.id,action_at); select * into s from public.focus_sessions where id=s.id;
 if s.status in('completed','discarded') then return public.api_error('SESSION_NOT_ACTIVE','{}',public.session_json(s.id)); end if;
 if s.health_check_state<>'pending' or s.status<>'focusing' then return public.api_error('HEALTH_CHECK_NOT_PENDING','{}',public.session_json(s.id)); end if;
 if p_choice='end' then
   perform public.finish_focus_session(s.id,action_at,'health_check_accepted');
   perform private.run_space_goal_maintenance(s.space_id,action_at);
 else
   update public.focus_sessions set health_check_state='continued',health_check_deadline_at=null,version=version+1 where id=s.id;
   perform public.record_focus_event(s.id,a,'health_check_continued',action_at);
 end if;
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
 return public.store_command(a,p_idempotency_key,'respond_focus_health_check',h,s.id,result);
end $$;
revoke all on function public.respond_focus_health_check(uuid,text,uuid) from public,anon;
grant execute on function public.respond_focus_health_check(uuid,text,uuid) to authenticated;

create function public.mark_focus_health_result_seen(p_session_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if not exists(select 1 from public.focus_sessions where id=p_session_id and user_id=a and completion_reason in('health_check_accepted','health_check_timeout')) then
   return public.api_error('SESSION_NOT_FOUND');
 end if;
 insert into private.health_check_result_reads(user_id,session_id) values(a,p_session_id) on conflict do nothing;
 return public.api_ok(jsonb_build_object('session_id',p_session_id,'seen',true));
end $$;
revoke all on function public.mark_focus_health_result_seen(uuid) from public,anon;
grant execute on function public.mark_focus_health_result_seen(uuid) to authenticated;

create function public.report_focus_health_notification(p_session_id uuid,p_shown boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); event_value public.focus_event_type;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if not exists(select 1 from public.focus_sessions where id=p_session_id and user_id=a and health_check_triggered_at is not null) then return public.api_error('SESSION_NOT_FOUND'); end if;
 event_value:=case when p_shown then 'health_check_notification_succeeded'::public.focus_event_type else 'health_check_notification_failed'::public.focus_event_type end;
 if not exists(select 1 from public.focus_events where session_id=p_session_id and event_type=event_value) then
   perform public.record_focus_event(p_session_id,a,event_value,now());
 end if;
 return public.api_ok(jsonb_build_object('recorded',true));
end $$;
revoke all on function public.report_focus_health_notification(uuid,boolean) from public,anon;
grant execute on function public.report_focus_health_notification(uuid,boolean) to authenticated;

create or replace function public.get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; a uuid:=private.current_principal_id(); acknowledged integer:=0;
begin
 result:=private.rpc_impl_get_home_snapshot(p_space_id);
 if result->>'ok'='true' then
   select health_check_policy_version into acknowledged from public.profiles where id=a;
   result:=jsonb_set(result,'{data,health_check_policy}',jsonb_build_object(
     'current_version',1,'acknowledged_version',coalesce(acknowledged,0),'enabled',private.focus_health_check_enabled()),true);
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
