alter function public.run_goal_maintenance(timestamptz) rename to run_goal_maintenance_before_missed_goal_fix;
revoke all on function public.run_goal_maintenance_before_missed_goal_fix(timestamptz) from public,anon,authenticated;

create function public.run_goal_maintenance(p_at timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare activated_count int:=0; output jsonb;
begin
 update public.goals set status='active'
 where status='scheduled' and starts_at<=p_at;
 get diagnostics activated_count=row_count;
 output:=public.run_goal_maintenance_before_missed_goal_fix(p_at);
 return jsonb_set(output,'{activated_goals}',to_jsonb(activated_count+coalesce((output->>'activated_goals')::int,0)));
end $$;
revoke all on function public.run_goal_maintenance(timestamptz) from public,anon,authenticated;

alter function private.run_space_goal_maintenance(uuid,timestamptz) rename to run_space_goal_maintenance_before_missed_goal_fix;
revoke all on function private.run_space_goal_maintenance_before_missed_goal_fix(uuid,timestamptz) from public,anon,authenticated;

create function private.run_space_goal_maintenance(p_space_id uuid,p_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare activated_count int:=0; output jsonb;
begin
 update public.goals set status='active'
 where space_id=p_space_id and status='scheduled' and starts_at<=p_at;
 get diagnostics activated_count=row_count;
 output:=private.run_space_goal_maintenance_before_missed_goal_fix(p_space_id,p_at);
 return jsonb_set(output,'{activated_goals}',to_jsonb(activated_count+coalesce((output->>'activated_goals')::int,0)));
end $$;
revoke all on function private.run_space_goal_maintenance(uuid,timestamptz) from public,anon,authenticated;

create or replace function public.finish_focus_session(p_session_id uuid,p_at timestamptz,p_reason public.completion_reason) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; v_end timestamptz; v_total int; v_status public.focus_status; v_uncertain int:=0; v_closed_seconds numeric:=0;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in('completed','discarded') then return p_session_id; end if;
 v_end:=case when s.status='paused' then s.paused_at else p_at end;
 select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds from public.focus_segments where session_id=s.id and ended_at is not null;
 if s.status='focusing' then
  v_end:=least(v_end,s.active_segment_started_at+make_interval(secs=>(21600-v_closed_seconds)::double precision));
  update public.focus_segments set ended_at=v_end where session_id=s.id and ended_at is null;
 end if;
 select coalesce(floor(sum(extract(epoch from(v_end-started_at))) filter(where started_at<v_end)),0)::int into v_uncertain
 from public.focus_connection_intervals where session_id=s.id and ended_at is null;
 update public.focus_connection_intervals set ended_at=v_end where session_id=s.id and ended_at is null and started_at<v_end;
 delete from public.focus_connection_intervals where session_id=s.id and ended_at is null and started_at>=v_end;
 select least(21600,coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::int) into v_total from public.focus_segments where session_id=s.id and ended_at is not null;
 v_status:=case when v_total<300 then 'discarded'::public.focus_status else 'completed'::public.focus_status end;
 update public.focus_sessions set status=v_status,accumulated_focus_seconds=v_total,active_segment_started_at=null,paused_at=null,completed_at=v_end,
  completion_reason=p_reason,unconfirmed_connection_seconds=unconfirmed_connection_seconds+v_uncertain,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,auth.uid(),'completed',v_end,jsonb_build_object('reason',p_reason));
 return s.id;
end $$;
revoke all on function public.finish_focus_session(uuid,timestamptz,public.completion_reason) from public,anon,authenticated;

create or replace function private.rpc_impl_end_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=coalesce(p_session_id::text,''); cached jsonb; s public.focus_sessions%rowtype; result jsonb; action_at timestamptz:=now(); was_final boolean;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'end_focus',h); if cached is not null then return cached; end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.user_id<>a then return public.api_error('SESSION_NOT_FOUND'); end if;
 if s.status not in('completed','discarded') and exists(select 1 from public.space_members where id=s.member_id and status='disabled') then return public.api_error('MEMBER_DISABLED'); end if;
 was_final:=s.status in('completed','discarded');
 if not was_final then perform public.settle_session(s.id,action_at); select * into s from public.focus_sessions where id=s.id; end if;
 if s.status not in('completed','discarded') then perform public.finish_focus_session(s.id,action_at,'manual_end'); end if;
 if not was_final then perform private.run_space_goal_maintenance(s.space_id,action_at); end if;
 result:=public.api_ok(jsonb_build_object('session',public.session_json(s.id)));
 return public.store_command(a,p_idempotency_key,'end_focus',h,s.id,result);
end $$;
revoke all on function private.rpc_impl_end_focus(uuid,uuid) from public,anon,authenticated;
