begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000151'),
 ('00000000-0000-0000-0000-000000000152'),
 ('00000000-0000-0000-0000-000000000153');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000151','UTC'),
 ('00000000-0000-0000-0000-000000000152','UTC'),
 ('00000000-0000-0000-0000-000000000153','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000151','Protected room','00000000-0000-0000-0000-000000000151','UTC','rls-protected'),
 ('10000000-0000-0000-0000-000000000153','Other room','00000000-0000-0000-0000-000000000153','UTC','rls-other');
insert into public.space_members(id,space_id,user_id,display_name,role,status,disabled_at,disabled_by) values
 ('20000000-0000-0000-0000-000000000151','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000151','Owner','owner','active',null,null),
 ('20000000-0000-0000-0000-000000000152','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000152','Disabled','member','disabled',now(),'00000000-0000-0000-0000-000000000151'),
 ('20000000-0000-0000-0000-000000000153','10000000-0000-0000-0000-000000000153','00000000-0000-0000-0000-000000000153','Outsider','owner','active',null,null);
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason) values
 ('40000000-0000-0000-0000-000000000151','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151','Protected task','completed',300,now()-interval '5 minutes',now(),'manual_end');
insert into public.focus_segments(id,session_id,started_at,ended_at) values('41000000-0000-0000-0000-000000000151','40000000-0000-0000-0000-000000000151',now()-interval '5 minutes',now());
insert into public.focus_events(session_id,actor_id,event_type) values('40000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000151','completed');
insert into public.focus_connection_intervals(id,session_id,started_at,ended_at,detected_from_last_seen_at) values('42000000-0000-0000-0000-000000000151','40000000-0000-0000-0000-000000000151',now()-interval '2 minutes',now()-interval '1 minute',now()-interval '3 minutes');
insert into public.focus_commands(actor_id,idempotency_key,command_type,request_hash,session_id,result) values('00000000-0000-0000-0000-000000000151','30000000-0000-0000-0000-000000000151','end_focus','hash','40000000-0000-0000-0000-000000000151','{}');
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values('50000000-0000-0000-0000-000000000151','10000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151','group_total_minutes','daily',5,'accepted',now()+interval '1 day',now()+interval '1 day',now(),now());
insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at) values('50000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151','accepted',now());
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status) values('60000000-0000-0000-0000-000000000151','50000000-0000-0000-0000-000000000151','10000000-0000-0000-0000-000000000151','group_total_minutes','daily',5,now()+interval '1 day',now()+interval '2 days','scheduled');
insert into public.goal_participants(goal_id,member_id) values('60000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151');
insert into public.achievements(id,space_id,achievement_type,dedupe_key) values('70000000-0000-0000-0000-000000000151','10000000-0000-0000-0000-000000000151','test','rls-test');
insert into public.achievement_reads(achievement_id,member_id) values('70000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000151');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',true);
select is((select count(*)::int from public.profiles where id='00000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read another profile');
select is((select count(*)::int from public.spaces where id='10000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read another space');
select is((select count(*)::int from public.space_members where space_id='10000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read members');
select is((select count(*)::int from public.focus_sessions where id='40000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read sessions');
select is((select count(*)::int from public.focus_segments where session_id='40000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read segments');
select is((select count(*)::int from public.focus_events where session_id='40000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read events');
select throws_ok($$select * from public.focus_connection_intervals$$,'42501',null,'cross-room user has no direct interval-table privilege');
select throws_ok($$select * from public.focus_commands$$,'42501',null,'cross-room user has no direct command-table privilege');
select is((select count(*)::int from public.goal_proposals where id='50000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read proposals');
select is((select count(*)::int from public.goal_proposal_members where proposal_id='50000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read proposal voters');
select is((select count(*)::int from public.goals where id='60000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read goals');
select is((select count(*)::int from public.goal_participants where goal_id='60000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read goal participants');
select is((select count(*)::int from public.achievements where id='70000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read achievements');
select is((select count(*)::int from public.achievement_reads where achievement_id='70000000-0000-0000-0000-000000000151'),0,'cross-room user cannot read achievement reads');
select throws_ok($$select * from public.personal_focus_goal_defaults$$,'42501',null,'cross-room user cannot read personal goal defaults');
select throws_ok($$select * from public.personal_focus_goal_overrides$$,'42501',null,'cross-room user cannot read personal goal overrides');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select is((select count(*)::int from public.profiles where id='00000000-0000-0000-0000-000000000151'),0,'disabled member cannot read another profile');
select is((select count(*)::int from public.spaces where id='10000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former space');
select is((select count(*)::int from public.space_members where space_id='10000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former members');
select is((select count(*)::int from public.focus_sessions where id='40000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former sessions');
select is((select count(*)::int from public.focus_segments where session_id='40000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former segments');
select is((select count(*)::int from public.focus_events where session_id='40000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former events');
select throws_ok($$select * from public.focus_connection_intervals$$,'42501',null,'disabled member has no direct interval-table privilege');
select throws_ok($$select * from public.focus_commands$$,'42501',null,'disabled member has no direct command-table privilege');
select is((select count(*)::int from public.goal_proposals where id='50000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former proposals');
select is((select count(*)::int from public.goal_proposal_members where proposal_id='50000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former proposal voters');
select is((select count(*)::int from public.goals where id='60000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former goals');
select is((select count(*)::int from public.goal_participants where goal_id='60000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former goal participants');
select is((select count(*)::int from public.achievements where id='70000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former achievements');
select is((select count(*)::int from public.achievement_reads where achievement_id='70000000-0000-0000-0000-000000000151'),0,'disabled member cannot read former achievement reads');
select throws_ok($$select * from public.personal_focus_goal_defaults$$,'42501',null,'disabled member cannot read personal goal defaults');
select throws_ok($$select * from public.personal_focus_goal_overrides$$,'42501',null,'disabled member cannot read personal goal overrides');

select * from finish();
rollback;
