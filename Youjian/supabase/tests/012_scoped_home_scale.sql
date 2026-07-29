begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000141'),('00000000-0000-0000-0000-000000000142'),
 ('00000000-0000-0000-0000-000000000143'),('00000000-0000-0000-0000-000000000144'),
 ('00000000-0000-0000-0000-000000000145');
insert into public.profiles(id,timezone) select id,'UTC' from auth.users where id::text like '00000000-0000-0000-0000-00000000014%';
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000141','Scoped A','00000000-0000-0000-0000-000000000141','UTC','scoped-a'),
 ('10000000-0000-0000-0000-000000000143','Scoped B','00000000-0000-0000-0000-000000000143','UTC','scoped-b'),
 ('10000000-0000-0000-0000-000000000144','Scale C','00000000-0000-0000-0000-000000000144','UTC','scale-c'),
 ('10000000-0000-0000-0000-000000000145','Scale D','00000000-0000-0000-0000-000000000145','UTC','scale-d');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000141','10000000-0000-0000-0000-000000000141','00000000-0000-0000-0000-000000000141','Owner A','owner'),
 ('20000000-0000-0000-0000-000000000142','10000000-0000-0000-0000-000000000141','00000000-0000-0000-0000-000000000142','Friend A','member'),
 ('20000000-0000-0000-0000-000000000143','10000000-0000-0000-0000-000000000143','00000000-0000-0000-0000-000000000143','Owner B','owner'),
 ('20000000-0000-0000-0000-000000000144','10000000-0000-0000-0000-000000000144','00000000-0000-0000-0000-000000000144','Owner C','owner'),
 ('20000000-0000-0000-0000-000000000145','10000000-0000-0000-0000-000000000145','00000000-0000-0000-0000-000000000145','Owner D','owner');

insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,paused_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000141','10000000-0000-0000-0000-000000000141','00000000-0000-0000-0000-000000000141','20000000-0000-0000-0000-000000000141','Due A','paused',now()-interval '16 minutes',now()-interval '30 minutes',now()-interval '16 minutes'),
 ('40000000-0000-0000-0000-000000000143','10000000-0000-0000-0000-000000000143','00000000-0000-0000-0000-000000000143','20000000-0000-0000-0000-000000000143','Due B','paused',now()-interval '16 minutes',now()-interval '30 minutes',now()-interval '16 minutes');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,active_segment_started_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000142','10000000-0000-0000-0000-000000000141','00000000-0000-0000-0000-000000000142','20000000-0000-0000-0000-000000000142','Friend stale','focusing',now()-interval '5 minutes',now()-interval '5 minutes',now()-interval '3 minutes');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000141',now()-interval '30 minutes',now()-interval '20 minutes'),
 ('40000000-0000-0000-0000-000000000143',now()-interval '30 minutes',now()-interval '20 minutes');
insert into public.focus_segments(session_id,started_at) values('40000000-0000-0000-0000-000000000142',now()-interval '5 minutes');

insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values
 ('50000000-0000-0000-0000-000000000141','10000000-0000-0000-0000-000000000141','20000000-0000-0000-0000-000000000141','group_total_minutes','daily',100000,'accepted',now()+interval '1 day',now()-interval '1 hour',now()-interval '1 day',now()-interval '1 hour'),
 ('50000000-0000-0000-0000-000000000142','10000000-0000-0000-0000-000000000141','20000000-0000-0000-0000-000000000141','group_total_minutes','daily',1,'accepted',now()+interval '1 day',now()-interval '2 days',now()-interval '3 days',now()-interval '2 days'),
 ('50000000-0000-0000-0000-000000000143','10000000-0000-0000-0000-000000000143','20000000-0000-0000-0000-000000000143','group_total_minutes','daily',100000,'accepted',now()+interval '1 day',now()-interval '1 hour',now()-interval '1 day',now()-interval '1 hour'),
 ('50000000-0000-0000-0000-000000000144','10000000-0000-0000-0000-000000000141','20000000-0000-0000-0000-000000000141','group_total_minutes','daily',1,'pending',now()-interval '1 minute',now()+interval '1 day',now()-interval '2 days',null),
 ('50000000-0000-0000-0000-000000000145','10000000-0000-0000-0000-000000000143','20000000-0000-0000-0000-000000000143','group_total_minutes','daily',1,'pending',now()-interval '1 minute',now()+interval '1 day',now()-interval '2 days',null);
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status,completed_at) values
 ('60000000-0000-0000-0000-000000000141','50000000-0000-0000-0000-000000000141','10000000-0000-0000-0000-000000000141','group_total_minutes','daily',100000,now()-interval '1 hour',now()+interval '1 day','scheduled',null),
 ('60000000-0000-0000-0000-000000000142','50000000-0000-0000-0000-000000000142','10000000-0000-0000-0000-000000000141','group_total_minutes','daily',1,now()-interval '2 days',now()-interval '1 day','completed',now()-interval '1 day'),
 ('60000000-0000-0000-0000-000000000143','50000000-0000-0000-0000-000000000143','10000000-0000-0000-0000-000000000143','group_total_minutes','daily',100000,now()-interval '1 hour',now()+interval '1 day','scheduled',null);
insert into public.goal_participants(goal_id,member_id) values
 ('60000000-0000-0000-0000-000000000141','20000000-0000-0000-0000-000000000141'),
 ('60000000-0000-0000-0000-000000000142','20000000-0000-0000-0000-000000000141'),
 ('60000000-0000-0000-0000-000000000143','20000000-0000-0000-0000-000000000143');

set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
create temporary table home_result as select public.get_home_snapshot('10000000-0000-0000-0000-000000000141') result;
reset role;
select is((select status::text from public.focus_sessions where id='40000000-0000-0000-0000-000000000141'),'completed','home settles a due session in its own room');
select is((select status::text from public.focus_sessions where id='40000000-0000-0000-0000-000000000143'),'paused','home does not settle a due session in another room');
select ok(exists(select 1 from public.focus_connection_intervals where session_id='40000000-0000-0000-0000-000000000142' and ended_at is null),'home preserves stale connection detection in its room');
select is((select status::text from public.goal_proposals where id='50000000-0000-0000-0000-000000000144'),'expired','home expires proposals in its room');
select is((select status::text from public.goal_proposals where id='50000000-0000-0000-0000-000000000145'),'pending','home leaves another room proposal untouched');
select is((select status::text from public.goals where id='60000000-0000-0000-0000-000000000141'),'active','home activates its room goal');
select is((select status::text from public.goals where id='60000000-0000-0000-0000-000000000143'),'scheduled','home leaves another room goal untouched');
select is((select result#>>'{data,active_goal_summary,goal_id}' from home_result),'60000000-0000-0000-0000-000000000141','home returns the newly activated room goal');
select is((select result#>>'{data,focusing_members,0,connection,status}' from home_result),'unconfirmed','home keeps connection status semantics');
select ok(exists(select 1 from public.achievements where space_id='10000000-0000-0000-0000-000000000141' and achievement_type='first_goal'),'home preserves scoped achievement evaluation');
select ok(not exists(select 1 from private.maintenance_runs where source='lazy' and started_at>=now()),'home does not create a global lazy-maintenance run');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000141',true);
create temporary table goals_result as select public.get_goals_snapshot('10000000-0000-0000-0000-000000000141') result;
reset role;
select is((select result#>>'{data,space_id}' from goals_result),'10000000-0000-0000-0000-000000000141','goal snapshot carries an explicit route-space context');
select is((select status::text from public.goal_proposals where id='50000000-0000-0000-0000-000000000145'),'pending','goal snapshot maintenance leaves another room proposal untouched');

insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason)
select md5('scale-c-'||g)::uuid,'10000000-0000-0000-0000-000000000144'::uuid,'00000000-0000-0000-0000-000000000144'::uuid,'20000000-0000-0000-0000-000000000144'::uuid,'Scale C','completed'::public.focus_status,300,'2026-08-05 10:00:00+00'::timestamptz,'2026-08-05 10:05:00+00'::timestamptz,'manual_end'::public.completion_reason from generate_series(1,10000) g
union all
select md5('scale-d-'||g)::uuid,'10000000-0000-0000-0000-000000000145'::uuid,'00000000-0000-0000-0000-000000000145'::uuid,'20000000-0000-0000-0000-000000000145'::uuid,'Scale D','completed'::public.focus_status,300,'2026-08-05 10:00:00+00'::timestamptz,'2026-08-05 10:05:00+00'::timestamptz,'manual_end'::public.completion_reason from generate_series(1,10000) g;
insert into public.focus_segments(session_id,started_at,ended_at)
select md5('scale-c-'||g)::uuid,'2026-08-05 10:00:00+00'::timestamptz,'2026-08-05 10:05:00+00'::timestamptz from generate_series(1,10000) g
union all
select md5('scale-d-'||g)::uuid,'2026-08-05 10:00:00+00'::timestamptz,'2026-08-05 10:05:00+00'::timestamptz from generate_series(1,10000) g;
analyze public.focus_sessions; analyze public.focus_segments;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000144',true);
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000144','mine','monthly','2026-08-15')#>>'{data,credited_focus_seconds}','3000000','monthly stats count only the requested room across multi-room data');
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000144','mine','monthly','2026-08-15')#>>'{data,valid_session_count}','10000','monthly stats preserve valid-session count at 10k-room scale');
select ok(to_regclass('public.focus_sessions_completed_space_id') is not null and to_regclass('public.focus_sessions_completed_space_user_id') is not null,'monthly stats have room-scoped completed-session indexes');

create temporary table scale_timings(kind text,elapsed_ms numeric);
do $$declare i int; started timestamptz; begin
 for i in 1..20 loop started:=clock_timestamp(); perform public.get_home_snapshot('10000000-0000-0000-0000-000000000144'); insert into scale_timings values('home',extract(epoch from(clock_timestamp()-started))*1000); end loop;
 for i in 1..20 loop started:=clock_timestamp(); perform public.get_stats_summary('10000000-0000-0000-0000-000000000144','mine','monthly','2026-08-15'); insert into scale_timings values('stats',extract(epoch from(clock_timestamp()-started))*1000); end loop;
end$$;
select ok((select percentile_cont(0.95) within group(order by elapsed_ms)<300 from scale_timings where kind='home'),'home p95 stays below 300ms with 10k local and 10k unrelated sessions');
select ok((select percentile_cont(0.95) within group(order by elapsed_ms)<300 from scale_timings where kind='stats'),'monthly stats p95 stays below 300ms with 10k local and 10k unrelated sessions');
select ok(not exists(select 1 from private.maintenance_runs where source='lazy' and started_at>=now()),'scaled home calls still avoid global lazy maintenance');
select ok(position('run_minute_maintenance' in pg_get_functiondef('private.rpc_impl_get_home_snapshot(uuid)'::regprocedure))=0,'home implementation has no global maintenance call');

select * from finish();
rollback;
