begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000111'),
 ('00000000-0000-0000-0000-000000000112');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000111','UTC'),
 ('00000000-0000-0000-0000-000000000112','UTC');
insert into public.spaces(id,name,owner_id,timezone,daily_checkin_target_minutes,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000111','Boundary','00000000-0000-0000-0000-000000000111','UTC',5,'boundary-token-hash');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000111','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','Owner','owner'),
 ('20000000-0000-0000-0000-000000000112','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','Member','member');

-- Fractional segment durations must be summed before the final integer credit is floored.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason) values
 ('40000000-0000-0000-0000-000000000111','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','Fractional day','completed',1,'2026-07-28 08:00:00+00','2026-07-28 08:00:02+00','manual_end'),
 ('40000000-0000-0000-0000-000000000112','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','Fractional streak','completed',300,'2026-07-28 09:00:00+00','2026-07-28 09:05:01+00','manual_end'),
 ('40000000-0000-0000-0000-000000000113','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','Fractional goal','completed',60,'2026-07-29 09:00:00+00','2026-07-29 09:01:01+00','manual_end');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000111','2026-07-28 08:00:00+00','2026-07-28 08:00:00.6+00'),
 ('40000000-0000-0000-0000-000000000111','2026-07-28 08:00:01+00','2026-07-28 08:00:01.6+00'),
 ('40000000-0000-0000-0000-000000000112','2026-07-28 09:00:00+00','2026-07-28 09:04:59.6+00'),
 ('40000000-0000-0000-0000-000000000112','2026-07-28 09:05:00+00','2026-07-28 09:05:00.6+00'),
 ('40000000-0000-0000-0000-000000000113','2026-07-29 09:00:00+00','2026-07-29 09:00:59.6+00'),
 ('40000000-0000-0000-0000-000000000113','2026-07-29 09:01:00+00','2026-07-29 09:01:00.6+00');

select is(public.credited_seconds_for_day('10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','2026-07-28','UTC'),301,'daily credits floor once after summing all fractional segments');
select is(public.current_streak_days('10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','UTC','2026-07-28 12:00:00+00'),1,'streak qualification floors once per local day');

insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values
 ('50000000-0000-0000-0000-000000000111','10000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','group_total_minutes','daily',1,'accepted','2026-07-31 00:00:00+00','2026-07-29 00:00:00+00','2026-07-28 00:00:00+00','2026-07-28 01:00:00+00');
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status) values
 ('60000000-0000-0000-0000-000000000111','50000000-0000-0000-0000-000000000111','10000000-0000-0000-0000-000000000111','group_total_minutes','daily',1,'2026-07-29 00:00:00+00','2026-07-30 00:00:00+00','active');
insert into public.goal_participants(goal_id,member_id) values
 ('60000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000111','2026-07-29 12:00:00+00')#>>'{credited_value}','1','goal progress floors once after summing fractional segments');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000111','2026-07-29 12:00:00+00')#>>'{completed}','true','fractional goal segments can satisfy the exact minute target');
update public.goals set status='scheduled' where id='60000000-0000-0000-0000-000000000111';
select private.run_space_goal_maintenance('10000000-0000-0000-0000-000000000111','2026-07-31 00:00:00+00');
select is((select status::text from public.goals where id='60000000-0000-0000-0000-000000000111'),'completed','a scheduled goal that Cron entirely missed is evaluated before it can be failed');

-- Manual settlement recalculates goals in the same transaction and records the actor.
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values
 ('50000000-0000-0000-0000-000000000115','10000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','group_total_minutes','daily',1,'accepted',now()+interval '1 day',now()-interval '1 hour',now()-interval '2 hours',now()-interval '1 hour');
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status) values
 ('60000000-0000-0000-0000-000000000115','50000000-0000-0000-0000-000000000115','10000000-0000-0000-0000-000000000111','group_total_minutes','daily',1,now()-interval '1 hour',now()+interval '1 hour','active');
insert into public.goal_participants(goal_id,member_id) values('60000000-0000-0000-0000-000000000115','20000000-0000-0000-0000-000000000111');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,active_segment_started_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000115','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','Immediate goal','focusing',now()-interval '6 minutes',now()-interval '6 minutes',now());
insert into public.focus_segments(session_id,started_at) values('40000000-0000-0000-0000-000000000115',now()-interval '6 minutes');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',true);
create temporary table manual_end_result as select public.end_focus('40000000-0000-0000-0000-000000000115','30000000-0000-0000-0000-000000000115') result;
reset role;
select is((select result->>'ok' from manual_end_result),'true','manual end succeeds through the public safe wrapper');
select is((select status::text from public.goals where id='60000000-0000-0000-0000-000000000115'),'completed','manual end recalculates and completes the active goal in the same transaction');
select is((select actor_id from public.focus_events where session_id='40000000-0000-0000-0000-000000000115' and event_type='completed'),'00000000-0000-0000-0000-000000000111'::uuid,'manual completion event records the authenticated actor');

-- A connection interval detected after the precise four-hour cutoff must not remain open.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,active_segment_started_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000114','10000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','Four hour cutoff','focusing',now()-interval '14410 seconds',now()-interval '14410 seconds',now()-interval '10 seconds');
insert into public.focus_segments(session_id,started_at) values
 ('40000000-0000-0000-0000-000000000114',now()-interval '14410 seconds');
insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values
 ('40000000-0000-0000-0000-000000000114',now()-interval '5 seconds',now()-interval '10 seconds');
select lives_ok($$select public.finish_focus_session('40000000-0000-0000-0000-000000000114',now(),'focus_limit')$$,'four-hour auto settlement accepts a post-cutoff open connection interval');
select is((select accumulated_focus_seconds from public.focus_sessions where id='40000000-0000-0000-0000-000000000114'),14400,'four-hour settlement credits exactly the cap');
select is((select count(*)::int from public.focus_connection_intervals where session_id='40000000-0000-0000-0000-000000000114' and ended_at is null),0,'four-hour settlement leaves no open connection interval');

-- A proposal accepted near expiry starts in the next period after approval, not creation.
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at) values
 ('50000000-0000-0000-0000-000000000112','10000000-0000-0000-0000-000000000111','20000000-0000-0000-0000-000000000111','group_total_minutes','daily',10,'pending',now()+interval '1 hour',date_trunc('day',now()-interval '46 hours')+interval '1 day',now()-interval '47 hours');
insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at) values
 ('50000000-0000-0000-0000-000000000112','20000000-0000-0000-0000-000000000111','accepted',now()-interval '47 hours'),
 ('50000000-0000-0000-0000-000000000112','20000000-0000-0000-0000-000000000112','accepted',now());
select ok(public.accept_proposal_if_ready('50000000-0000-0000-0000-000000000112',now()) is not null,'fully approved late proposal is accepted');
select ok((select starts_at>now() from public.goals where source_proposal_id='50000000-0000-0000-0000-000000000112'),'late proposal starts in a future complete period');
select is((select p.effective_period_start=g.starts_at from public.goal_proposals p join public.goals g on g.source_proposal_id=p.id where p.id='50000000-0000-0000-0000-000000000112'),true,'proposal and goal retain the same approval-based effective period');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',true);
select is(public.report_client_error('UI_BOUNDARY','/home',jsonb_build_object('context',jsonb_build_object('invite_token','secret')))#>>'{error,code}','SENSITIVE_METADATA_REJECTED','nested sensitive error metadata is rejected');
select is(public.report_client_error('UI_BOUNDARY','/invite/secret-token','{}')#>>'{error,code}','INVALID_ERROR_REPORT','invite-token routes are rejected');
select ok(public.report_client_error('UI_BOUNDARY','/home',jsonb_build_object('context',jsonb_build_object('component','Home')))#>>'{data,report_id}' is not null,'safe nested error metadata is accepted');
select is(public.list_focus_history('10000000-0000-0000-0000-000000000111','mine',now()-interval '367 days',now(),30,null)#>>'{error,code}','INVALID_RANGE','history rejects ranges longer than 366 days');
select ok(public.list_focus_history('10000000-0000-0000-0000-000000000111','mine',now()-interval '366 days',now(),30,null)#>'{data,items}' is not null,'history accepts the documented 366-day maximum');

select * from finish();
rollback;
