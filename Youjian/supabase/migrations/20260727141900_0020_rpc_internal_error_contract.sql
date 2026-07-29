create table private.rpc_internal_errors(
 request_id uuid primary key,
 actor_id uuid,
 rpc_name text not null check(rpc_name~'^[a-z0-9_]{1,80}$'),
 error_code text not null check(error_code~'^[0-9A-Z]{5}$'),
 occurred_at timestamptz not null default now()
);
revoke all on private.rpc_internal_errors from public,anon,authenticated;

create function private.rpc_internal_error_envelope(p_rpc_name text,p_error_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rid uuid:=gen_random_uuid(); safe_code text;
begin
 safe_code:=case when coalesce(p_error_code,'')~'^[0-9A-Z]{5}$' then p_error_code else 'XX000' end;
 insert into private.rpc_internal_errors(request_id,actor_id,rpc_name,error_code) values(rid,auth.uid(),p_rpc_name,safe_code);
 return public.api_error('INTERNAL_ERROR',jsonb_build_object('request_id',rid));
end $$;
revoke all on function private.rpc_internal_error_envelope(text,text) from public,anon,authenticated;

create or replace function private.run_minute_maintenance_as(p_source text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare run_id bigint; output jsonb; t timestamptz:=now(); started_clock timestamptz:=clock_timestamp(); duration int;
begin
 if p_source not in('cron','lazy','manual') then raise exception 'invalid maintenance source' using errcode='22023'; end if;
 insert into private.maintenance_runs(job_name,started_at,status,source) values('minute_maintenance',t,'running',p_source) returning id into run_id;
 begin
  delete from private.invite_preview_rate_limits where window_start<t-interval '1 day';
  delete from private.invite_preview_rate_buckets where window_start<t-interval '1 day';
  delete from private.client_error_rate_limits where window_start<t-interval '1 day';
  delete from private.client_error_reports where occurred_at<t-interval '90 days';
  delete from private.rpc_internal_errors where occurred_at<t-interval '90 days';
  delete from private.maintenance_runs where started_at<t-interval '30 days' and id<>run_id;
  output:=public.run_minute_maintenance_core(t); duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='succeeded',result=output where id=run_id; return output;
 exception when others then
  duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='failed',error_code=sqlstate,result=jsonb_build_object('message','maintenance failed') where id=run_id;
  return jsonb_build_object('ok',false,'error_code','MAINTENANCE_FAILED','run_id',run_id,'ran_at',t);
 end;
end $$;
revoke all on function private.run_minute_maintenance_as(text) from public,anon,authenticated;

alter function public.create_space(text,text,text,text,smallint,uuid) set schema private;
alter function private.create_space(text,text,text,text,smallint,uuid) rename to rpc_impl_create_space;
alter function public.disable_member(uuid,uuid,uuid) set schema private;
alter function private.disable_member(uuid,uuid,uuid) rename to rpc_impl_disable_member;
alter function public.end_focus(uuid,uuid) set schema private;
alter function private.end_focus(uuid,uuid) rename to rpc_impl_end_focus;
alter function public.get_focus_session_detail(uuid) set schema private;
alter function private.get_focus_session_detail(uuid) rename to rpc_impl_get_focus_session_detail;
alter function public.get_goals_snapshot(uuid) set schema private;
alter function private.get_goals_snapshot(uuid) rename to rpc_impl_get_goals_snapshot;
alter function public.get_home_snapshot(uuid) set schema private;
alter function private.get_home_snapshot(uuid) rename to rpc_impl_get_home_snapshot;
alter function public.get_invite_preview(text) set schema private;
alter function private.get_invite_preview(text) rename to rpc_impl_get_invite_preview;
alter function public.get_my_membership() set schema private;
alter function private.get_my_membership() rename to rpc_impl_get_my_membership;
alter function public.get_space_settings(uuid) set schema private;
alter function private.get_space_settings(uuid) rename to rpc_impl_get_space_settings;
alter function public.get_stats_summary(uuid,text,text,date) set schema private;
alter function private.get_stats_summary(uuid,text,text,date) rename to rpc_impl_get_stats_summary;
alter function public.heartbeat_focus(uuid) set schema private;
alter function private.heartbeat_focus(uuid) rename to rpc_impl_heartbeat_focus;
alter function public.join_space(text,text,text,uuid) set schema private;
alter function private.join_space(text,text,text,uuid) rename to rpc_impl_join_space;
alter function public.list_achievements(uuid,integer,text) set schema private;
alter function private.list_achievements(uuid,integer,text) rename to rpc_impl_list_achievements;
alter function public.list_focus_history(uuid,text,timestamptz,timestamptz,integer,text) set schema private;
alter function private.list_focus_history(uuid,text,timestamptz,timestamptz,integer,text) rename to rpc_impl_list_focus_history;
alter function public.mark_achievement_seen(uuid,uuid) set schema private;
alter function private.mark_achievement_seen(uuid,uuid) rename to rpc_impl_mark_achievement_seen;
alter function public.pause_focus(uuid,uuid) set schema private;
alter function private.pause_focus(uuid,uuid) rename to rpc_impl_pause_focus;
alter function public.propose_goal(uuid,text,text,integer,uuid) set schema private;
alter function private.propose_goal(uuid,text,text,integer,uuid) rename to rpc_impl_propose_goal;
alter function public.report_client_error(text,text,jsonb) set schema private;
alter function private.report_client_error(text,text,jsonb) rename to rpc_impl_report_client_error;
alter function public.resume_focus(uuid,uuid) set schema private;
alter function private.resume_focus(uuid,uuid) rename to rpc_impl_resume_focus;
alter function public.rotate_invite(uuid,uuid) set schema private;
alter function private.rotate_invite(uuid,uuid) rename to rpc_impl_rotate_invite;
alter function public.start_focus(uuid,text,text,uuid) set schema private;
alter function private.start_focus(uuid,text,text,uuid) rename to rpc_impl_start_focus;
alter function public.vote_goal_proposal(uuid,text,uuid) set schema private;
alter function private.vote_goal_proposal(uuid,text,uuid) rename to rpc_impl_vote_goal_proposal;

create function public.create_space(p_display_name text,p_space_name text,p_space_timezone text,p_profile_timezone text,p_member_limit smallint,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_create_space(p_display_name,p_space_name,p_space_timezone,p_profile_timezone,p_member_limit,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('create_space',sqlstate); end$$;
create function public.disable_member(p_space_id uuid,p_member_id uuid,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_disable_member(p_space_id,p_member_id,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('disable_member',sqlstate); end$$;
create function public.end_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_end_focus(p_session_id,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('end_focus',sqlstate); end$$;
create function public.get_focus_session_detail(p_session_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_focus_session_detail(p_session_id); exception when others then return private.rpc_internal_error_envelope('get_focus_session_detail',sqlstate); end$$;
create function public.get_goals_snapshot(p_space_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_goals_snapshot(p_space_id); exception when others then return private.rpc_internal_error_envelope('get_goals_snapshot',sqlstate); end$$;
create function public.get_home_snapshot(p_space_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_home_snapshot(p_space_id); exception when others then return private.rpc_internal_error_envelope('get_home_snapshot',sqlstate); end$$;
create function public.get_invite_preview(p_invite_token text) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_invite_preview(p_invite_token); exception when others then return private.rpc_internal_error_envelope('get_invite_preview',sqlstate); end$$;
create function public.get_my_membership() returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_my_membership(); exception when others then return private.rpc_internal_error_envelope('get_my_membership',sqlstate); end$$;
create function public.get_space_settings(p_space_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_space_settings(p_space_id); exception when others then return private.rpc_internal_error_envelope('get_space_settings',sqlstate); end$$;
create function public.get_stats_summary(p_space_id uuid,p_view text,p_period text,p_anchor_local_date date) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_get_stats_summary(p_space_id,p_view,p_period,p_anchor_local_date); exception when others then return private.rpc_internal_error_envelope('get_stats_summary',sqlstate); end$$;
create function public.heartbeat_focus(p_session_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_heartbeat_focus(p_session_id); exception when others then return private.rpc_internal_error_envelope('heartbeat_focus',sqlstate); end$$;
create function public.join_space(p_invite_token text,p_display_name text,p_profile_timezone text,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_join_space(p_invite_token,p_display_name,p_profile_timezone,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('join_space',sqlstate); end$$;
create function public.list_achievements(p_space_id uuid,p_limit integer default 30,p_cursor text default null) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_list_achievements(p_space_id,p_limit,p_cursor); exception when others then return private.rpc_internal_error_envelope('list_achievements',sqlstate); end$$;
create function public.list_focus_history(p_space_id uuid,p_view text,p_period_start timestamptz,p_period_end timestamptz,p_limit integer default 30,p_cursor text default null) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_list_focus_history(p_space_id,p_view,p_period_start,p_period_end,p_limit,p_cursor); exception when others then return private.rpc_internal_error_envelope('list_focus_history',sqlstate); end$$;
create function public.mark_achievement_seen(p_achievement_id uuid,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_mark_achievement_seen(p_achievement_id,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('mark_achievement_seen',sqlstate); end$$;
create function public.pause_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_pause_focus(p_session_id,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('pause_focus',sqlstate); end$$;
create function public.propose_goal(p_space_id uuid,p_goal_type text,p_period_type text,p_target_value integer,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_propose_goal(p_space_id,p_goal_type,p_period_type,p_target_value,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('propose_goal',sqlstate); end$$;
create function public.report_client_error(p_error_code text,p_route text default null,p_metadata jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_report_client_error(p_error_code,p_route,p_metadata); exception when others then return private.rpc_internal_error_envelope('report_client_error',sqlstate); end$$;
create function public.resume_focus(p_session_id uuid,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_resume_focus(p_session_id,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('resume_focus',sqlstate); end$$;
create function public.rotate_invite(p_space_id uuid,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_rotate_invite(p_space_id,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('rotate_invite',sqlstate); end$$;
create function public.start_focus(p_space_id uuid,p_task_name text,p_category text,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_start_focus(p_space_id,p_task_name,p_category,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('start_focus',sqlstate); end$$;
create function public.vote_goal_proposal(p_proposal_id uuid,p_vote text,p_idempotency_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin return private.rpc_impl_vote_goal_proposal(p_proposal_id,p_vote,p_idempotency_key); exception when others then return private.rpc_internal_error_envelope('vote_goal_proposal',sqlstate); end$$;

revoke all on function public.create_space(text,text,text,text,smallint,uuid),public.disable_member(uuid,uuid,uuid),public.end_focus(uuid,uuid),public.get_focus_session_detail(uuid),public.get_goals_snapshot(uuid),public.get_home_snapshot(uuid),public.get_invite_preview(text),public.get_my_membership(),public.get_space_settings(uuid),public.get_stats_summary(uuid,text,text,date),public.heartbeat_focus(uuid),public.join_space(text,text,text,uuid),public.list_achievements(uuid,integer,text),public.list_focus_history(uuid,text,timestamptz,timestamptz,integer,text),public.mark_achievement_seen(uuid,uuid),public.pause_focus(uuid,uuid),public.propose_goal(uuid,text,text,integer,uuid),public.report_client_error(text,text,jsonb),public.resume_focus(uuid,uuid),public.rotate_invite(uuid,uuid),public.start_focus(uuid,text,text,uuid),public.vote_goal_proposal(uuid,text,uuid) from public;
grant execute on function public.get_invite_preview(text) to anon,authenticated;
grant execute on function public.create_space(text,text,text,text,smallint,uuid),public.disable_member(uuid,uuid,uuid),public.end_focus(uuid,uuid),public.get_focus_session_detail(uuid),public.get_goals_snapshot(uuid),public.get_home_snapshot(uuid),public.get_my_membership(),public.get_space_settings(uuid),public.get_stats_summary(uuid,text,text,date),public.heartbeat_focus(uuid),public.join_space(text,text,text,uuid),public.list_achievements(uuid,integer,text),public.list_focus_history(uuid,text,timestamptz,timestamptz,integer,text),public.mark_achievement_seen(uuid,uuid),public.pause_focus(uuid,uuid),public.propose_goal(uuid,text,text,integer,uuid),public.report_client_error(text,text,jsonb),public.resume_focus(uuid,uuid),public.rotate_invite(uuid,uuid),public.start_focus(uuid,text,text,uuid),public.vote_goal_proposal(uuid,text,uuid) to authenticated;

revoke all on function private.rpc_impl_create_space(text,text,text,text,smallint,uuid),private.rpc_impl_disable_member(uuid,uuid,uuid),private.rpc_impl_end_focus(uuid,uuid),private.rpc_impl_get_focus_session_detail(uuid),private.rpc_impl_get_goals_snapshot(uuid),private.rpc_impl_get_home_snapshot(uuid),private.rpc_impl_get_invite_preview(text),private.rpc_impl_get_my_membership(),private.rpc_impl_get_space_settings(uuid),private.rpc_impl_get_stats_summary(uuid,text,text,date),private.rpc_impl_heartbeat_focus(uuid),private.rpc_impl_join_space(text,text,text,uuid),private.rpc_impl_list_achievements(uuid,integer,text),private.rpc_impl_list_focus_history(uuid,text,timestamptz,timestamptz,integer,text),private.rpc_impl_mark_achievement_seen(uuid,uuid),private.rpc_impl_pause_focus(uuid,uuid),private.rpc_impl_propose_goal(uuid,text,text,integer,uuid),private.rpc_impl_report_client_error(text,text,jsonb),private.rpc_impl_resume_focus(uuid,uuid),private.rpc_impl_rotate_invite(uuid,uuid),private.rpc_impl_start_focus(uuid,text,text,uuid),private.rpc_impl_vote_goal_proposal(uuid,text,uuid) from public,anon,authenticated;
