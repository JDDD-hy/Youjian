begin;
create extension if not exists pgtap with schema extensions;
select plan(27);
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000021');
insert into public.profiles(id,timezone) values ('00000000-0000-0000-0000-000000000021','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000021','Focus','00000000-0000-0000-0000-000000000021','UTC','focus-hash');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000021','Timer','owner');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
set local role authenticated;

select is(public.start_focus('10000000-0000-0000-0000-000000000021','Short','study','30000000-0000-0000-0000-000000000021')#>>'{data,session,status}','focusing','start creates focusing session');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '299 seconds' where status='focusing';
update public.focus_segments set started_at=now()-interval '299 seconds' where ended_at is null;
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select is(public.end_focus((select id from public.focus_sessions where task_name='Short'),'30000000-0000-0000-0000-000000000022')#>>'{data,session,status}','discarded','299 seconds is discarded');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Short'),299,'discarded duration is exact');

select is(public.start_focus('10000000-0000-0000-0000-000000000021','Threshold','work','30000000-0000-0000-0000-000000000023')#>>'{data,session,status}','focusing','second session starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '300 seconds' where status='focusing'; update public.focus_segments set started_at=now()-interval '300 seconds' where ended_at is null;
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select is(public.end_focus((select id from public.focus_sessions where task_name='Threshold'),'30000000-0000-0000-0000-000000000024')#>>'{data,session,status}','completed','300 seconds is completed');
select ok((select count(*)=1 from public.focus_events e join public.focus_sessions s on s.id=e.session_id where s.task_name='Threshold' and e.event_type='completed'),'settlement emits exactly one completed event');
reset role;
select throws_ok($$update public.focus_sessions set task_name='Mutated' where task_name='Threshold'$$,'55000',null,'settled history cannot be modified');
select throws_ok($$delete from public.focus_segments where session_id=(select id from public.focus_sessions where task_name='Threshold')$$,'55000',null,'closed segments cannot be deleted');

set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000021','Paused','reading','30000000-0000-0000-0000-000000000025')$$,'paused scenario starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '600 seconds' where status='focusing'; update public.focus_segments set started_at=now()-interval '600 seconds' where ended_at is null;
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select is(public.pause_focus((select id from public.focus_sessions where task_name='Paused'),'30000000-0000-0000-0000-000000000026')#>>'{data,session,status}','paused','pause closes active segment');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Paused'),600,'pause stores focused seconds only');
reset role;
update public.focus_sessions set paused_at=now()-interval '15 minutes' where task_name='Paused';
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select is(public.resume_focus((select id from public.focus_sessions where task_name='Paused'),'30000000-0000-0000-0000-000000000027')#>>'{data,session,completion_reason}','pause_timeout','resume at 15 minutes auto-settles');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Paused'),600,'pause timeout adds no paused time');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000021','Limit','exercise','30000000-0000-0000-0000-000000000028')$$,'limit scenario starts');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '21604 seconds' where status='focusing'; update public.focus_segments set started_at=now()-interval '21604 seconds' where ended_at is null;
select lives_ok($$select public.run_minute_maintenance()$$,'late cron settles due focus');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Limit'),21600,'late cron caps focus at exactly six hours');
select is((select completion_reason::text from public.focus_sessions where task_name='Limit'),'focus_limit','six-hour reason is authoritative');
select is((select extract(epoch from(s.completed_at-g.started_at))::int from public.focus_sessions s join public.focus_segments g on g.session_id=s.id where s.task_name='Limit'),21600,'completion timestamp is exact cutoff, not cron time');
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select is(public.end_focus((select id from public.focus_sessions where task_name='Limit'),'30000000-0000-0000-0000-000000000029')#>>'{data,session,completion_reason}','focus_limit','end after cron preserves final reason');
select is((select count(*)::int from public.focus_events e join public.focus_sessions s on s.id=e.session_id where s.task_name='Limit' and e.event_type='completed'),1,'cron/end race leaves one completion event');

select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000021','Fractional','study','30000000-0000-0000-0000-000000000031')$$,'fractional scenario starts');
reset role; update public.focus_sessions set active_segment_started_at=now()-interval '0.6 seconds' where task_name='Fractional'; update public.focus_segments set started_at=now()-interval '0.6 seconds' where ended_at is null;
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select lives_ok($$select public.pause_focus((select id from public.focus_sessions where task_name='Fractional'),'30000000-0000-0000-0000-000000000032')$$,'fractional first segment pauses');
select lives_ok($$select public.resume_focus((select id from public.focus_sessions where task_name='Fractional'),'30000000-0000-0000-0000-000000000033')$$,'fractional session resumes');
reset role; update public.focus_sessions set active_segment_started_at=now()-interval '299.6 seconds' where task_name='Fractional'; update public.focus_segments set started_at=now()-interval '299.6 seconds' where session_id=(select id from public.focus_sessions where task_name='Fractional') and ended_at is null;
set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select is(public.end_focus((select id from public.focus_sessions where task_name='Fractional'),'30000000-0000-0000-0000-000000000034')#>>'{data,session,credited_focus_seconds}','300','fractional segments are summed before final floor');

select is(public.start_focus('10000000-0000-0000-0000-000000000021','Idempotent','other','30000000-0000-0000-0000-000000000030'),
 public.start_focus('10000000-0000-0000-0000-000000000021','Idempotent','other','30000000-0000-0000-0000-000000000030'),'start retry returns identical response');
select is((select count(*)::int from public.focus_sessions where task_name='Idempotent'),1,'start retry creates one record');
reset role;
select throws_ok($$insert into public.focus_sessions(space_id,user_id,member_id,task_name,category,status,active_segment_started_at)
 values('10000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000021','Concurrent','work','focusing',now())$$,
 '23505',null,'partial unique index prevents concurrent active sessions');

select * from finish();
rollback;
