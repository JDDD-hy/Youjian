begin;
set local timezone='UTC';
create extension if not exists pgtap with schema extensions;
select plan(16);

select set_eq(
  'select name from private.iana_timezones',
  'select name from pg_catalog.pg_timezone_names',
  'cached timezone names exactly match the server catalog'
);
select ok(
  public.validate_iana_timezone('Europe/Paris')
  and public.validate_iana_timezone('Asia/Shanghai')
  and public.validate_iana_timezone('UTC')
  and public.validate_iana_timezone('Etc/GMT+3'),
  'IANA names and existing aliases remain valid'
);
select ok(
  not public.validate_iana_timezone(null)
  and not public.validate_iana_timezone('')
  and not public.validate_iana_timezone('Mars/Olympus')
  and not public.validate_iana_timezone('europe/paris')
  and not public.validate_iana_timezone(' Europe/Paris ')
  and not public.validate_iana_timezone('+03:00'),
  'nulls, invented names, case changes, whitespace and numeric offsets stay invalid'
);
select ok(not has_table_privilege('anon','private.iana_timezones','select'),'anonymous clients cannot read the internal cache');
select ok(not has_table_privilege('authenticated','private.iana_timezones','select'),'authenticated clients cannot read the internal cache');
select ok(not has_table_privilege('authenticated','private.iana_timezones','update'),'clients cannot change accepted timezone names');
select is(
  (select command from cron.job where jobname='youjian-timezone-cache-refresh' and active),
  'refresh materialized view concurrently private.iana_timezones',
  'timezone cache refreshes through the private server job'
);
select lives_ok('refresh materialized view concurrently private.iana_timezones','concurrent refresh remains runnable');
select has_index('private','maintenance_runs','maintenance_runs_started_at','retention cleanup has a time index');

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000341'),
 ('00000000-0000-0000-0000-000000000342'),
 ('00000000-0000-0000-0000-000000000343');
insert into public.profiles(id,timezone)
select id,'UTC' from auth.users where id in(
 '00000000-0000-0000-0000-000000000341',
 '00000000-0000-0000-0000-000000000342',
 '00000000-0000-0000-0000-000000000343'
);
insert into public.spaces(id,name,owner_id,timezone,daily_checkin_target_minutes,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000341','Solo query fixture','00000000-0000-0000-0000-000000000341','UTC',30,'query-solo'),
 ('10000000-0000-0000-0000-000000000342','Shared query fixture','00000000-0000-0000-0000-000000000342','UTC',30,'query-shared');
insert into public.space_members(id,space_id,user_id,display_name,role,joined_at) values
 ('20000000-0000-0000-0000-000000000341','10000000-0000-0000-0000-000000000341','00000000-0000-0000-0000-000000000341','Solo','owner',now()-interval '4 days'),
 ('20000000-0000-0000-0000-000000000342','10000000-0000-0000-0000-000000000342','00000000-0000-0000-0000-000000000342','Owner','owner',now()-interval '4 days'),
 ('20000000-0000-0000-0000-000000000343','10000000-0000-0000-0000-000000000342','00000000-0000-0000-0000-000000000343','Friend','member',now()-interval '4 days');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason)
select gen_random_uuid(),space_id,user_id,id,'Query fixture','completed',1800,
 date_trunc('day',now())-d*interval '1 day',date_trunc('day',now())-d*interval '1 day'+interval '30 minutes','manual_end'
from public.space_members cross join generate_series(0,2) d where id in(
 '20000000-0000-0000-0000-000000000341',
 '20000000-0000-0000-0000-000000000342',
 '20000000-0000-0000-0000-000000000343'
);
insert into public.focus_segments(session_id,started_at,ended_at)
select id,started_at,completed_at from public.focus_sessions where task_name='Query fixture';
insert into public.achievements(space_id,achievement_type,dedupe_key,earned_at,metadata)
values('10000000-0000-0000-0000-000000000342','together_lit','together-lit:'||(current_date-2),now(),jsonb_build_object('local_date',current_date-2));

select lives_ok('select public.run_goal_maintenance(now())','scheduled goal maintenance still evaluates shared daily facts');
select is((select count(*)::int from public.achievements where space_id='10000000-0000-0000-0000-000000000341' and achievement_type='together_lit'),0,'solo rooms do not earn a shared daily fact');
select is((select count(*)::int from public.achievements where space_id='10000000-0000-0000-0000-000000000342' and achievement_type='together_lit'),3,'two qualifying members earn both missing daily facts');
select is((select metadata->>'days' from public.achievements where space_id='10000000-0000-0000-0000-000000000342' and dedupe_key='together-streak-day:'||current_date),'3','older daily facts are processed first so today keeps its full streak');
select lives_ok($$select private.run_space_goal_maintenance('10000000-0000-0000-0000-000000000342',now())$$,'room-scoped maintenance accepts an already awarded day');
select is((select count(*)::int from public.achievements where space_id='10000000-0000-0000-0000-000000000342' and achievement_type='together_lit'),3,'repeated maintenance keeps daily facts idempotent');
select is((select count(*)::int from public.achievement_participants ap join public.achievements a on a.id=ap.achievement_id where a.space_id='10000000-0000-0000-0000-000000000342' and a.achievement_type='together_lit'),6,'daily facts retain both participant snapshots');

select * from finish();
rollback;
