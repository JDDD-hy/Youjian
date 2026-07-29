begin;
create extension if not exists pgtap with schema extensions;
select plan(34);
insert into auth.users(id) values('00000000-0000-0000-0000-000000000091'),('00000000-0000-0000-0000-000000000092'),('00000000-0000-0000-0000-000000000093');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000091','UTC'),('00000000-0000-0000-0000-000000000092','UTC'),('00000000-0000-0000-0000-000000000093','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000091','Audit','00000000-0000-0000-0000-000000000091','UTC',public.invite_hash('rate-token-abcdefghijklmnopqrstuvwxyz-1234567890')),
 ('10000000-0000-0000-0000-000000000093','Other','00000000-0000-0000-0000-000000000093','UTC','other-audit');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000091','Owner','owner'),
 ('20000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000092','Member','member'),
 ('20000000-0000-0000-0000-000000000093','10000000-0000-0000-0000-000000000093','00000000-0000-0000-0000-000000000093','Other','owner');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,active_segment_started_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','Timer audit','focusing',now()-interval '600 seconds',now()-interval '600 seconds',now()-interval '130 seconds');
insert into public.focus_segments(session_id,started_at) values('40000000-0000-0000-0000-000000000091',now()-interval '600 seconds');
insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values('40000000-0000-0000-0000-000000000091',now()-interval '10 seconds',now()-interval '130 seconds');

set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select is(public.pause_focus('40000000-0000-0000-0000-000000000091','30000000-0000-0000-0000-000000000091')#>>'{error,code}',public.pause_focus('40000000-0000-0000-0000-000000000999','30000000-0000-0000-0000-000000000092')#>>'{error,code}','pause does not enumerate another session');
select is(public.resume_focus('40000000-0000-0000-0000-000000000091','30000000-0000-0000-0000-000000000093')#>>'{error,code}','SESSION_NOT_FOUND','resume does not enumerate another session');
select is(public.end_focus('40000000-0000-0000-0000-000000000091','30000000-0000-0000-0000-000000000094')#>>'{error,code}','SESSION_NOT_FOUND','end does not enumerate another session');
select is(public.heartbeat_focus('40000000-0000-0000-0000-000000000091')#>>'{error,code}','SESSION_NOT_FOUND','heartbeat does not enumerate another session');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select is(public.pause_focus('40000000-0000-0000-0000-000000000091','30000000-0000-0000-0000-000000000095')#>>'{data,session,status}','paused','owner pauses active session');
reset role;
select is((select count(*)::int from public.focus_connection_intervals where session_id='40000000-0000-0000-0000-000000000091' and ended_at is null),0,'pause closes open uncertainty interval');
select is((select unconfirmed_connection_seconds from public.focus_sessions where id='40000000-0000-0000-0000-000000000091'),10,'pause records uncertainty only until pause');
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select is(public.heartbeat_focus('40000000-0000-0000-0000-000000000091')#>>'{data,session,connection,unconfirmed_connection_seconds}','10','heartbeat returns refreshed accumulated uncertainty');
select is(public.start_focus('10000000-0000-0000-0000-000000000091','Null category',null,'30000000-0000-0000-0000-000000000096')#>>'{error,code}','INVALID_CATEGORY','null start category has stable error');
select is(public.start_focus('10000000-0000-0000-0000-000000000091','Null key','work',null)#>>'{error,code}','INVALID_IDEMPOTENCY_KEY','null idempotency key has stable error');
select is(public.create_space('X','Y','UTC','UTC',null,'30000000-0000-0000-0000-000000000097')#>>'{error,code}','INVALID_MEMBER_LIMIT','null member limit has stable error');

reset role;
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values
 ('50000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','group_total_minutes','weekly',100000,'accepted',now()+interval '48 hours',now()-interval '1 hour',now()-interval '1 day',now()-interval '1 hour'),
 ('50000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','group_total_minutes','daily',10,'accepted',now()+interval '48 hours',now()-interval '1 day',now()-interval '2 days',now()-interval '1 day'),
 ('50000000-0000-0000-0000-000000000093','10000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','group_total_minutes','daily',10,'accepted',now()+interval '48 hours',now()-interval '1 day',now()-interval '2 days',now()-interval '1 day'),
 ('50000000-0000-0000-0000-000000000094','10000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','shared_checkin_days','daily',1,'pending',now(),now()+interval '1 day',now()-interval '48 hours',null),
 ('50000000-0000-0000-0000-000000000095','10000000-0000-0000-0000-000000000093','20000000-0000-0000-0000-000000000093','group_total_minutes','weekly',10,'pending',now()+interval '48 hours',now()+interval '1 day',now(),null);
insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at) values('50000000-0000-0000-0000-000000000095','20000000-0000-0000-0000-000000000093',null,null);
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status,completed_at) values
 ('60000000-0000-0000-0000-000000000091','50000000-0000-0000-0000-000000000091','10000000-0000-0000-0000-000000000091','group_total_minutes','weekly',100000,now()-interval '1 hour',now()+interval '1 day','active',null),
 ('60000000-0000-0000-0000-000000000092','50000000-0000-0000-0000-000000000092','10000000-0000-0000-0000-000000000091','group_total_minutes','daily',10,now()-interval '2 days',now()-interval '1 day','completed',now()-interval '1 day'),
 ('60000000-0000-0000-0000-000000000093','50000000-0000-0000-0000-000000000093','10000000-0000-0000-0000-000000000091','group_total_minutes','daily',10,now()-interval '2 days',now()-interval '1 day','completed',now()-interval '1 day');
insert into public.goal_participants(goal_id,member_id) values('60000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091');
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values
 ('50000000-0000-0000-0000-000000000096','10000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000091','group_total_minutes','daily',10,'accepted',now()+interval '48 hours',now()-interval '3 days',now()-interval '4 days',now()-interval '3 days');
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status) values
 ('60000000-0000-0000-0000-000000000096','50000000-0000-0000-0000-000000000096','10000000-0000-0000-0000-000000000091','group_total_minutes','daily',10,now()-interval '3 days',now()-interval '2 days','scheduled');

set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select is(public.vote_goal_proposal('50000000-0000-0000-0000-000000000094',null,'30000000-0000-0000-0000-000000000098')#>>'{error,code}','INVALID_VOTE','null vote has stable error');
select is(public.propose_goal('10000000-0000-0000-0000-000000000091','group_total_minutes','weekly',2147483647,'30000000-0000-0000-0000-000000000099')#>>'{error,code}','INVALID_TARGET_VALUE','oversized target is rejected before arithmetic');
select is(public.propose_goal('10000000-0000-0000-0000-000000000091','group_total_minutes','weekly',10,'30000000-0000-0000-0000-000000000101')#>>'{data,proposal,goal_type}','group_total_minutes','group-total goal proposal works');
select is(public.propose_goal('10000000-0000-0000-0000-000000000091','per_member_minutes','monthly',10,'30000000-0000-0000-0000-000000000102')#>>'{data,proposal,goal_type}','per_member_minutes','per-member goal proposal works');
select is(public.propose_goal('10000000-0000-0000-0000-000000000091','shared_checkin_days','weekly',3,'30000000-0000-0000-0000-000000000103')#>>'{data,proposal,goal_type}','shared_checkin_days','shared-checkin goal proposal works');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',true);
select is(public.vote_goal_proposal('50000000-0000-0000-0000-000000000095','accepted','30000000-0000-0000-0000-000000000104')#>>'{error,code}',public.vote_goal_proposal('50000000-0000-0000-0000-000000000999','accepted','30000000-0000-0000-0000-000000000105')#>>'{error,code}','cross-space proposal is not enumerable');
reset role;
select lives_ok($$select public.run_goal_maintenance(now())$$,'goal maintenance handles exact boundaries');
select is((select status::text from public.goal_proposals where id='50000000-0000-0000-0000-000000000094'),'expired','proposal expires at exact 48-hour boundary');
select is((select status::text from public.goals where id='60000000-0000-0000-0000-000000000096'),'failed','missed scheduled goal does not remain stuck');
select is((select count(*)::int from public.achievements where space_id='10000000-0000-0000-0000-000000000091' and achievement_type='first_goal'),1,'multiple completed goals grant first_goal once');
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000091')#>>'{data,active_goal_summary,goal_id}','60000000-0000-0000-0000-000000000091','home returns real active goal summary');
select is(public.disable_member('10000000-0000-0000-0000-000000000091','20000000-0000-0000-0000-000000000092','30000000-0000-0000-0000-000000000106')#>>'{data,member,status}','disabled','owner disables member under the shared space lock');
select is(public.propose_goal('10000000-0000-0000-0000-000000000091','group_total_minutes','weekly',10,'30000000-0000-0000-0000-000000000107')#>>'{error,code}','NOT_ENOUGH_MEMBERS','proposal recounts active members after acquiring lock');

reset role; select set_config('request.headers','{"x-forwarded-for":"203.0.113.9","x-client-fingerprint":"audit-device"}',true);
do $$begin for i in 1..30 loop perform public.get_invite_preview('rate-token-abcdefghijklmnopqrstuvwxyz-1234567890'); end loop; end$$;
set local role anon;
select is(public.get_invite_preview('rate-token-abcdefghijklmnopqrstuvwxyz-1234567890')#>>'{error,code}','RATE_LIMITED','preview rate limit uses fixed token and client window');
reset role; select set_config('request.headers','{"x-forwarded-for":"203.0.113.9","x-client-fingerprint":"rotated-device"}',true); set local role anon;
select is(public.get_invite_preview('rate-token-abcdefghijklmnopqrstuvwxyz-1234567890')#>>'{error,code}','RATE_LIMITED','changing a client-controlled fingerprint cannot bypass the IP and token limit');
reset role;
select ok(not exists(select 1 from private.invite_preview_rate_limits where token_hash like '%rate-token%'),'rate-limit storage contains only hashes');
insert into private.invite_preview_rate_limits(token_hash,client_hash,window_start,request_count) values('expired-window','expired-client',now()-interval '2 days',1);
select lives_ok($$select public.run_minute_maintenance()$$,'maintenance wrapper runs');
select ok(not exists(select 1 from private.invite_preview_rate_limits where token_hash='expired-window'),'maintenance removes expired rate-limit windows');
select ok((select count(*)>0 and bool_and(status='succeeded' and finished_at is not null and duration_ms is not null) from private.maintenance_runs where started_at=now()),'maintenance runs have persistent success and duration audit');
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000091',true);
select throws_ok($$select * from private.maintenance_runs$$,'42501',null,'clients cannot read maintenance audit');
select ok(public.report_client_error('UI_BOUNDARY','/home',jsonb_build_object('component','Home'))#>>'{data,report_id}' is not null,'authenticated client can report de-identified error');
select is(public.report_client_error('UI_BOUNDARY','/home',jsonb_build_object('invite_token','secret'))#>>'{error,code}','SENSITIVE_METADATA_REJECTED','client report rejects sensitive metadata');
reset role; select ok((select count(*)=1 and bool_and(not(metadata ? 'invite_token')) from private.client_error_reports where actor_id='00000000-0000-0000-0000-000000000091'),'private client-error audit stores only accepted de-identified report');
select * from finish(); rollback;
