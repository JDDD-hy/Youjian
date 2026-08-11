begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

insert into auth.users(id) values ('00000000-0000-0000-0000-000000000251');
insert into public.profiles(id,timezone) values ('00000000-0000-0000-0000-000000000251','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000251','Health check','00000000-0000-0000-0000-000000000251','UTC','health-check-hash');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000251','10000000-0000-0000-0000-000000000251','00000000-0000-0000-0000-000000000251','Timer','owner');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select is(public.start_focus('10000000-0000-0000-0000-000000000251','Needs policy','study','UTC',1,'30000000-0000-0000-0000-000000000251')#>>'{error,code}','HEALTH_POLICY_ACK_REQUIRED','policy-aware start requires acknowledgement');
select is(public.acknowledge_focus_health_policy(1)#>>'{data,acknowledged_version}','1','policy v1 acknowledgement is stored');
select is(public.start_focus('10000000-0000-0000-0000-000000000251','Continue choice','study','UTC',1,'30000000-0000-0000-0000-000000000252')#>>'{data,session,health_check,state}','waiting','new policy-aware session is eligible');
reset role;

update public.focus_sessions set active_segment_started_at=now()-interval '2 hours' where task_name='Continue choice';
update public.focus_segments set started_at=now()-interval '2 hours' where session_id=(select id from public.focus_sessions where task_name='Continue choice') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='Continue choice'),now());
select is((select health_check_state from public.focus_sessions where task_name='Continue choice'),'pending','two effective hours trigger one pending check');
select is((select count(*)::int from public.focus_events e join public.focus_sessions s on s.id=e.session_id where s.task_name='Continue choice' and e.event_type='health_check_triggered'),1,'trigger event is unique');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select is(public.respond_focus_health_check((select id from public.focus_sessions where task_name='Continue choice'),'continue','30000000-0000-0000-0000-000000000253')#>>'{data,session,health_check,state}','continued','continue resolves the check without ending focus');
select is(public.end_focus((select id from public.focus_sessions where task_name='Continue choice'),'30000000-0000-0000-0000-000000000254')#>>'{data,session,completion_reason}','manual_end','continued session still ends normally');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000251','Timeout choice','work','UTC',1,'30000000-0000-0000-0000-000000000255')$$,'second eligible session starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '2 hours 1 minute 5 seconds' where task_name='Timeout choice';
update public.focus_segments set started_at=now()-interval '2 hours 1 minute 5 seconds' where session_id=(select id from public.focus_sessions where task_name='Timeout choice') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='Timeout choice'),now());
select is((select completion_reason::text from public.focus_sessions where task_name='Timeout choice'),'health_check_timeout','late maintenance settles at the health deadline');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Timeout choice'),7260,'maintenance delay is excluded from credited focus');
select is((select count(*)::int from public.focus_events e join public.focus_sessions s on s.id=e.session_id where s.task_name='Timeout choice' and e.event_type='completed'),1,'timeout settlement emits one completion');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select is(public.respond_focus_health_check((select id from public.focus_sessions where task_name='Timeout choice'),'continue','30000000-0000-0000-0000-000000000256')#>>'{error,code}','SESSION_NOT_ACTIVE','late continue cannot revive a timed-out session');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000251','Recent rest','reading','UTC',1,'30000000-0000-0000-0000-000000000257')$$,'recent-rest scenario starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '95 minutes' where task_name='Recent rest';
update public.focus_segments set started_at=now()-interval '95 minutes' where session_id=(select id from public.focus_sessions where task_name='Recent rest') and ended_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.pause_focus((select id from public.focus_sessions where task_name='Recent rest'),'30000000-0000-0000-0000-000000000258')$$,'qualifying rest begins');
reset role;
update public.focus_sessions set paused_at=now()-interval '5 minutes' where task_name='Recent rest';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.resume_focus((select id from public.focus_sessions where task_name='Recent rest'),'30000000-0000-0000-0000-000000000259')$$,'five-minute rest resumes');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '25 minutes' where task_name='Recent rest';
update public.focus_segments set started_at=now()-interval '25 minutes' where session_id=(select id from public.focus_sessions where task_name='Recent rest') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='Recent rest'),now());
select is((select health_check_state from public.focus_sessions where task_name='Recent rest'),'satisfied_by_pause','five-minute rest within the final thirty focus minutes satisfies the check');
select is((select count(*)::int from public.focus_events e join public.focus_sessions s on s.id=e.session_id where s.task_name='Recent rest' and e.event_type='health_check_triggered'),0,'pause exemption avoids a prompt');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.end_focus((select id from public.focus_sessions where task_name='Recent rest'),'30000000-0000-0000-0000-000000000260')$$,'exempt session can end normally');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000251','Pending rest','study','UTC',1,'30000000-0000-0000-0000-000000000262')$$,'pending-rest scenario starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '2 hours' where task_name='Pending rest';
update public.focus_segments set started_at=now()-interval '2 hours' where session_id=(select id from public.focus_sessions where task_name='Pending rest') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='Pending rest'),now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.pause_focus((select id from public.focus_sessions where task_name='Pending rest'),'30000000-0000-0000-0000-000000000263')$$,'pausing suspends a pending deadline');
select is((select health_check_deadline_at::text from public.focus_sessions where task_name='Pending rest'),null,'pending deadline is suspended while paused');
reset role;
update public.focus_sessions set paused_at=now()-interval '5 minutes' where task_name='Pending rest';
select public.settle_session((select id from public.focus_sessions where task_name='Pending rest'),now());
select is((select health_check_state from public.focus_sessions where task_name='Pending rest'),'satisfied_by_pause','five paused minutes satisfy an already pending check');
select is((select status::text from public.focus_sessions where task_name='Pending rest'),'paused','health satisfaction does not resume or end the session');
select is((select count(*)::int from public.focus_events e join public.focus_sessions s on s.id=e.session_id where s.task_name='Pending rest' and e.event_type='health_check_satisfied_by_pause'),1,'pending pause satisfaction event is unique');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.end_focus((select id from public.focus_sessions where task_name='Pending rest'),'30000000-0000-0000-0000-000000000264')$$,'pause-satisfied session can end normally');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000251','Short pending rest','study','UTC',1,'30000000-0000-0000-0000-000000000265')$$,'short pending-rest scenario starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '2 hours' where task_name='Short pending rest';
update public.focus_segments set started_at=now()-interval '2 hours' where session_id=(select id from public.focus_sessions where task_name='Short pending rest') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='Short pending rest'),now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.pause_focus((select id from public.focus_sessions where task_name='Short pending rest'),'30000000-0000-0000-0000-000000000266')$$,'short pause suspends the deadline');
reset role;
update public.focus_sessions set paused_at=now()-interval '4 minutes' where task_name='Short pending rest';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.resume_focus((select id from public.focus_sessions where task_name='Short pending rest'),'30000000-0000-0000-0000-000000000267')$$,'resuming before five minutes keeps the check pending');
select is((select health_check_state from public.focus_sessions where task_name='Short pending rest'),'pending','short rest does not satisfy the check');
select ok((select health_check_deadline_at between now()+interval '59 seconds' and now()+interval '61 seconds' from public.focus_sessions where task_name='Short pending rest'),'short-rest resume receives a fresh full minute');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '1 second' where task_name='Short pending rest';
update public.focus_segments set started_at=now()-interval '1 second' where session_id=(select id from public.focus_sessions where task_name='Short pending rest') and ended_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000251',true);
select lives_ok($$select public.respond_focus_health_check((select id from public.focus_sessions where task_name='Short pending rest'),'end','30000000-0000-0000-0000-000000000268')$$,'resumed pending check can be accepted');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000251','Emergency off','other','UTC',1,'30000000-0000-0000-0000-000000000261')$$,'emergency-switch scenario starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '2 hours' where task_name='Emergency off';
update public.focus_segments set started_at=now()-interval '2 hours' where session_id=(select id from public.focus_sessions where task_name='Emergency off') and ended_at is null;
select public.settle_session((select id from public.focus_sessions where task_name='Emergency off'),now());
update private.feature_flags set enabled=false,updated_at=now() where name='focus_health_check_v1';
select public.settle_session((select id from public.focus_sessions where task_name='Emergency off'),now());
select is((select health_check_state from public.focus_sessions where task_name='Emergency off'),'cancelled','server emergency switch cancels an unresolved check');
select is((select status::text from public.focus_sessions where task_name='Emergency off'),'focusing','emergency cancellation leaves the session running');

select * from finish();
rollback;
