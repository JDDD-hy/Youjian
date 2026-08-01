create or replace function private.focus_task_history_json(p_session_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'task_name', e.metadata->>'old_task_name',
        'category', e.metadata->>'old_category',
        'changed_at', e.occurred_at
      ) order by e.occurred_at desc, e.id desc
    ),
    '[]'::jsonb
  )
  from public.focus_events e
  where e.session_id = p_session_id
    and e.event_type = 'task_updated'
$$;

create or replace function public.session_json(p_session_id uuid, p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object(
   'session_id', s.id, 'space_id', s.space_id, 'member_id', s.member_id, 'task_name', s.task_name,
   'category', s.category, 'task_history', private.focus_task_history_json(s.id),
   'status', s.status, 'started_at', s.started_at,
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

create or replace function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); sp public.spaces%rowtype; me public.space_members%rowtype; my_sid uuid; friends jsonb; today_seconds int; streak int; today_date date; profile_tz text; active_count int; active_goal jsonb; snapshot_at timestamptz:=now();
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into sp from public.spaces where id=p_space_id; select * into me from public.space_members where space_id=p_space_id and user_id=a and status='active'; select timezone into profile_tz from public.profiles where id=a;
 perform private.run_space_maintenance(p_space_id,snapshot_at);
 select id into my_sid from public.focus_sessions where user_id=a and status in('focusing','paused'); select count(*) into active_count from public.space_members where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name,'session_id',s.id,'task_name',s.task_name,'category',s.category,'task_history',private.focus_task_history_json(s.id),'status',s.status,'accumulated_focus_seconds',s.accumulated_focus_seconds,'active_segment_started_at',s.active_segment_started_at,'connection',jsonb_build_object('status',case when snapshot_at-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,'last_seen_at',s.last_seen_at))order by m.joined_at),'[]') into friends
 from public.focus_sessions s join public.space_members m on m.id=s.member_id where s.space_id=p_space_id and s.user_id<>a and s.status='focusing' and m.status='active';
 today_date:=(snapshot_at at time zone profile_tz)::date; today_seconds:=public.credited_seconds_for_day(p_space_id,a,today_date,profile_tz); streak:=public.current_streak_days(p_space_id,a,profile_tz,snapshot_at);
 select public.goal_json(id) into active_goal from public.goals where space_id=p_space_id and status='active' order by ends_at,id limit 1;
 return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sp.id,'name',sp.name,'timezone',sp.timezone,'active_member_count',active_count,'member_limit',sp.member_limit,'daily_checkin_target_minutes',sp.daily_checkin_target_minutes),
 'me',jsonb_build_object('member_id',me.id,'display_name',me.display_name,'role',me.role,'profile_timezone',profile_tz),'my_session',case when my_sid is null then null else public.session_json(my_sid) end,'focusing_members',friends,
 'today',jsonb_build_object('credited_focus_seconds',today_seconds,'checkin_target_seconds',sp.daily_checkin_target_minutes*60,'checkin_completed',today_seconds>=sp.daily_checkin_target_minutes*60,'current_streak_days',streak),
 'active_goal_summary',active_goal,'unseen_achievement',(select jsonb_build_object('achievement_id',ac.id,'achievement_type',ac.achievement_type,'earned_at',ac.earned_at,'metadata',ac.metadata) from public.achievements ac left join public.achievement_reads ar on ar.achievement_id=ac.id and ar.member_id=me.id where ac.space_id=p_space_id and ar.achievement_id is null order by ac.earned_at limit 1)));
end $$;

create function private.rpc_impl_update_focus_task(p_session_id uuid,p_task_name text,p_category text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text; cached jsonb; s public.focus_sessions%rowtype; cat public.focus_category; normalized_task text; result jsonb; changed_at timestamptz:=now();
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 normalized_task:=btrim(p_task_name);
 if p_task_name is null or char_length(normalized_task) not between 1 and 80 then return public.api_error('INVALID_TASK_NAME'); end if;
 if p_category is null then return public.api_error('INVALID_CATEGORY'); end if;
 begin cat:=p_category::public.focus_category; exception when invalid_text_representation then return public.api_error('INVALID_CATEGORY'); end;
 h:=encode(extensions.digest(convert_to(coalesce(p_session_id::text,'')||'|'||normalized_task||'|'||cat::text,'UTF8'),'sha256'),'hex');
 cached:=public.command_cached(a,p_idempotency_key,'update_focus_task',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found then return public.api_error('SESSION_NOT_FOUND'); end if;
 if s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 if exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 perform public.settle_session(s.id,changed_at); select * into s from public.focus_sessions where id=s.id;
 if s.status not in('focusing','paused') then return public.api_error('SESSION_NOT_ACTIVE','{}',public.session_json(s.id)); end if;
 if s.task_name=normalized_task and s.category=cat then
   result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
   return public.store_command(a,p_idempotency_key,'update_focus_task',h,s.id,result);
 end if;
 update public.focus_sessions set task_name=normalized_task,category=cat,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,a,'task_updated',changed_at,jsonb_build_object('old_task_name',s.task_name,'old_category',s.category,'new_task_name',normalized_task,'new_category',cat));
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
 return public.store_command(a,p_idempotency_key,'update_focus_task',h,s.id,result);
exception when check_violation or not_null_violation or invalid_text_representation then return public.api_error('INVALID_REQUEST');
end $$;

create function public.update_focus_task(p_session_id uuid,p_task_name text,p_category text,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 return private.rpc_impl_update_focus_task(p_session_id,p_task_name,p_category,p_idempotency_key);
exception when others then
 return private.rpc_internal_error_envelope('update_focus_task',sqlstate);
end $$;

revoke all on function private.focus_task_history_json(uuid),private.rpc_impl_update_focus_task(uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.update_focus_task(uuid,text,text,uuid) from public;
grant execute on function public.update_focus_task(uuid,text,text,uuid) to authenticated;
