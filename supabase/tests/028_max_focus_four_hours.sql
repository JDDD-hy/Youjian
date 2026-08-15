begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users(id) values ('00000000-0000-0000-0000-000000000281');
insert into public.profiles(id,timezone) values ('00000000-0000-0000-0000-000000000281','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000281','Four-hour policy','00000000-0000-0000-0000-000000000281','UTC','four-hour-policy-hash');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000281','10000000-0000-0000-0000-000000000281','00000000-0000-0000-0000-000000000281','Timer','owner');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000281',true);
select is(public.start_focus('10000000-0000-0000-0000-000000000281','Legacy caller','study','UTC','30000000-0000-0000-0000-000000000280')#>>'{data,session,max_focus_seconds}','14400','legacy start overload still receives the four-hour database default');
reset role;
select public.finish_focus_session((select id from public.focus_sessions where task_name='Legacy caller'),now()+interval '1 second','manual_end');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000281',true);
select is(public.acknowledge_focus_health_policy(2)#>>'{error,code}','CLIENT_UPDATE_REQUIRED','old acknowledgement overload cannot acknowledge policy v2');
select is(public.start_focus('10000000-0000-0000-0000-000000000281','Old v2 caller','study','UTC',2,'30000000-0000-0000-0000-000000000281')#>>'{error,code}','CLIENT_UPDATE_REQUIRED','old start overload cannot start policy v2');
select is(public.acknowledge_focus_health_policy(2,'wrong-contract')#>>'{error,code}','CLIENT_UPDATE_REQUIRED','v2 acknowledgement requires the four-hour capability contract');
select is(public.acknowledge_focus_health_policy(2,'max_focus_seconds=14400')#>>'{data,acknowledged_version}','2','explicit v2 contract acknowledgement succeeds');
select is(public.start_focus('10000000-0000-0000-0000-000000000281','V2 continue','study','UTC',2,'max_focus_seconds=14400','30000000-0000-0000-0000-000000000282')#>>'{data,session,max_focus_seconds}','14400','new v2 session exposes a four-hour cap');
reset role;

update public.focus_sessions set active_segment_started_at=now()-interval '2 hours' where task_name='V2 continue';
update public.focus_segments set started_at=now()-interval '2 hours' where session_id=(select id from public.focus_sessions where task_name='V2 continue') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='V2 continue'),now());
select is((select health_check_state from public.focus_sessions where task_name='V2 continue'),'pending','v2 still prompts once at two effective hours');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000281',true);
select is(public.respond_focus_health_check((select id from public.focus_sessions where task_name='V2 continue'),'continue','30000000-0000-0000-0000-000000000283')#>>'{data,session,health_check,state}','continued','continue keeps the v2 session active');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '4 hours 9 minutes' where task_name='V2 continue';
update public.focus_segments set started_at=now()-interval '4 hours 9 minutes' where session_id=(select id from public.focus_sessions where task_name='V2 continue') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='V2 continue'),now());
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='V2 continue'),14400,'late settlement credits exactly four hours');
select is((select completion_reason::text from public.focus_sessions where task_name='V2 continue'),'focus_limit','continued v2 session ends at the four-hour hard cap');
select is((select extract(epoch from(s.completed_at-g.started_at))::int from public.focus_sessions s join public.focus_segments g on g.session_id=s.id where s.task_name='V2 continue'),14400,'late settlement persists the logical four-hour cutoff');

-- Simulate an active row that existed before this migration and was backfilled.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,active_segment_started_at,last_seen_at,health_check_policy_version,health_check_state,max_focus_seconds)
values ('40000000-0000-0000-0000-000000000281','10000000-0000-0000-0000-000000000281','00000000-0000-0000-0000-000000000281','20000000-0000-0000-0000-000000000281','Legacy active','work','focusing',now()-interval '4 hours 1 minute',now()-interval '4 hours 1 minute',now(),1,'continued',21600);
insert into public.focus_segments(session_id,started_at) values ('40000000-0000-0000-0000-000000000281',now()-interval '4 hours 1 minute');
select public.run_minute_maintenance_core(now());
select is((select status::text from public.focus_sessions where task_name='Legacy active'),'focusing','scheduler does not select a legacy six-hour session at four hours');
select public.settle_session('40000000-0000-0000-0000-000000000281',now()+interval '2 hours 10 minutes');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Legacy active'),21600,'legacy active session retains the six-hour cap');
select is((select completion_reason::text from public.focus_sessions where task_name='Legacy active'),'focus_limit','legacy session still settles with focus_limit at six hours');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000281',true);
select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000281','Pause resume','reading','UTC',2,'max_focus_seconds=14400','30000000-0000-0000-0000-000000000284')$$,'pause/resume v2 session starts');
reset role;
update public.focus_sessions set accumulated_focus_seconds=7200,health_check_state='continued',active_segment_started_at=now()-interval '1 hour' where task_name='Pause resume';
update public.focus_segments set started_at=now()-interval '3 hours',ended_at=now()-interval '1 hour' where session_id=(select id from public.focus_sessions where task_name='Pause resume') and ended_at is null;
insert into public.focus_segments(session_id,started_at) values ((select id from public.focus_sessions where task_name='Pause resume'),now()-interval '1 hour');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000281',true);
select lives_ok($$select public.pause_focus((select id from public.focus_sessions where task_name='Pause resume'),'30000000-0000-0000-0000-000000000285')$$,'pause uses the per-session cap');
select lives_ok($$select public.resume_focus((select id from public.focus_sessions where task_name='Pause resume'),'30000000-0000-0000-0000-000000000286')$$,'resume after pause succeeds below four hours');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '1 hour' where task_name='Pause resume';
update public.focus_segments set started_at=now()-interval '1 hour' where session_id=(select id from public.focus_sessions where task_name='Pause resume') and ended_at is null;
select public.run_minute_maintenance_core(now());
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Pause resume'),14400,'scheduler settles paused-and-resumed v2 work at four cumulative hours');
select is((select max_focus_seconds from public.focus_sessions where task_name='Pause resume'),14400,'pause/resume preserves the immutable session cap');

-- Historical six-hour rows remain legal after the migration.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,max_focus_seconds)
values ('40000000-0000-0000-0000-000000000282','10000000-0000-0000-0000-000000000281','00000000-0000-0000-0000-000000000281','20000000-0000-0000-0000-000000000281','Historical six','study','completed',now()-interval '7 hours',now()-interval '1 hour','manual_end',21600,now()-interval '1 hour',21600);
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Historical six'),21600,'historical six-hour records remain valid');

select * from finish();
rollback;
