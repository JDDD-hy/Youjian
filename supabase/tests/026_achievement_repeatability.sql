begin;
create extension if not exists pgtap with schema extensions;
select plan(46);

update public.achievement_rule_versions
set enabled_at='2026-08-01 00:00:00+00'
where version='extended-v1';

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000301'),
  ('00000000-0000-0000-0000-000000000311'),
  ('00000000-0000-0000-0000-000000000312'),
  ('00000000-0000-0000-0000-000000000313'),
  ('00000000-0000-0000-0000-000000000314'),
  ('00000000-0000-0000-0000-000000000315');
insert into public.profiles(id,timezone) values
  ('00000000-0000-0000-0000-000000000301','UTC'),
  ('00000000-0000-0000-0000-000000000311','Asia/Shanghai'),
  ('00000000-0000-0000-0000-000000000312','Asia/Shanghai'),
  ('00000000-0000-0000-0000-000000000313','Asia/Shanghai'),
  ('00000000-0000-0000-0000-000000000314','Asia/Shanghai'),
  ('00000000-0000-0000-0000-000000000315','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash,daily_checkin_target_minutes) values
  ('10000000-0000-0000-0000-000000000301','Repeatability','00000000-0000-0000-0000-000000000301','UTC','repeatability',30),
  ('10000000-0000-0000-0000-000000000311','Living Flame','00000000-0000-0000-0000-000000000311','Asia/Shanghai','living-flame',30);
insert into public.space_members(id,space_id,user_id,display_name,role) values
  ('20000000-0000-0000-0000-000000000301','10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','Owner','owner'),
  ('20000000-0000-0000-0000-000000000311','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','One','owner'),
  ('20000000-0000-0000-0000-000000000312','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000312','Two','member'),
  ('20000000-0000-0000-0000-000000000313','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000313','Three','member'),
  ('20000000-0000-0000-0000-000000000314','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000314','Four','member'),
  ('20000000-0000-0000-0000-000000000315','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000315','Five','member');

create temporary table repeatability_source_sessions(
  id uuid primary key
) on commit drop;

-- Source sessions make the foreign-key and same-session idempotency paths real.
do $$
declare sid uuid; i integer;
begin
  for i in 1..21 loop
    sid:=gen_random_uuid();
    insert into public.focus_sessions(
      id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,
      completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot
    ) values(
      sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301',
      '20000000-0000-0000-0000-000000000301','Source '||i,'study','completed',
      timestamptz '2026-08-01 00:00:00+00'+make_interval(days=>i),
      timestamptz '2026-08-01 01:00:00+00'+make_interval(days=>i),
      'manual_end',3600,timestamptz '2026-08-01 01:00:00+00'+make_interval(days=>i),'UTC'
    ) returning id into sid;
    insert into repeatability_source_sessions values(sid);
  end loop;
end $$;

select ok(private.record_personal_achievement_event(
  '00000000-0000-0000-0000-000000000301','night_owl','10000000-0000-0000-0000-000000000301',
  (select id from repeatability_source_sessions order by id limit 1),'night-first','2026-08-02','2026-08-02 01:00:00+00','{}'
),'one-time achievement accepts its first event');
select ok(not private.record_personal_achievement_event(
  '00000000-0000-0000-0000-000000000301','night_owl','10000000-0000-0000-0000-000000000301',
  (select id from repeatability_source_sessions order by id desc limit 1),'night-second','2026-08-03','2026-08-03 01:00:00+00','{}'
),'one-time achievement blocks a later event even with a new key');
select is((select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='night_owl'),1,'one-time history remains one row');

do $$
declare sid uuid; i integer;
begin
  for i in 1..21 loop
    select id into sid from repeatability_source_sessions order by id offset i-1 limit 1;
    perform private.record_personal_achievement_event(
      '00000000-0000-0000-0000-000000000301','solo_focus','10000000-0000-0000-0000-000000000301',
      sid,'solo-'||i,'2026-08-01'::date+i,('2026-08-01 02:00:00+00'::timestamptz+make_interval(days=>i)),
      '{}'::jsonb
    );
  end loop;
end $$;
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='solo_focus'),21,'series events continue after the maximum stage');
select is((select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='solo_focus'),'gold','series tier remains capped at gold');
select is((select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='solo_focus' and notification_eligible),3,'only first and stage upgrades are notification events');
select ok(not (select notification_eligible from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='solo_focus' order by earned_at desc limit 1),'a post-cap series event is stored without a notification');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000301',true);
select is(jsonb_array_length((public.list_personal_achievements('10000000-0000-0000-0000-000000000301',30,null)#>'{data,items,0,events}')),3,'personal RPC hides ordinary repeat events');
select is((jsonb_path_query_first(public.list_personal_achievements('10000000-0000-0000-0000-000000000301',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "solo_focus")')->>'earned_at')::timestamptz,'2026-08-21 02:00:00+00'::timestamptz,'personal card date stays at the last stage unlock');
reset role;
select ok(not private.record_personal_achievement_event(
  '00000000-0000-0000-0000-000000000301','solo_focus','10000000-0000-0000-0000-000000000301',
  (select id from repeatability_source_sessions order by id limit 1),'solo-1','2026-08-02','2026-08-02 02:00:00+00','{}'
),'same-session repeat is rejected by the existing unique source-session constraint');

select ok(private.record_personal_achievement_event(
  '00000000-0000-0000-0000-000000000301','return_after_break','10000000-0000-0000-0000-000000000301',
  (select id from repeatability_source_sessions order by id limit 1),'legacy-return','2026-08-02','2026-08-02 03:00:00+00','{}'
),'legacy one-time row can be created');
update public.personal_achievements set count=7 where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='return_after_break';
select ok(not private.record_personal_achievement_event(
  '00000000-0000-0000-0000-000000000301','return_after_break','10000000-0000-0000-0000-000000000301',
  (select id from repeatability_source_sessions order by id desc limit 1),'legacy-return-repeat','2026-08-03','2026-08-03 03:00:00+00','{}'
),'legacy one-time history blocks new events without recalculation');
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='return_after_break'),7,'legacy count is preserved');

select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','chance_encounter','chance-1','2026-08-04 00:00:00+00','gold','{}',
  array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312']::uuid[]
),null,'shared one-time achievement accepts its first event');
select is(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','chance_encounter','chance-2','2026-08-05 00:00:00+00','gold','{}',
  array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312']::uuid[]
),null,'shared one-time achievement blocks a later event');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','fellow_travelers','fellow-3','2026-08-06 00:00:00+00','silver',
  jsonb_build_object('member_count',3),array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312','20000000-0000-0000-0000-000000000313']::uuid[]
),null,'shared series accepts its first stage');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','fellow_travelers','fellow-5','2026-08-07 00:00:00+00','gold',
  jsonb_build_object('member_count',5),array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312','20000000-0000-0000-0000-000000000313','20000000-0000-0000-0000-000000000314','20000000-0000-0000-0000-000000000315']::uuid[]
),null,'shared series reaches its maximum stage');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','fellow_travelers','fellow-5-repeat','2026-08-08 00:00:00+00','gold',
  jsonb_build_object('member_count',5),array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312','20000000-0000-0000-0000-000000000313','20000000-0000-0000-0000-000000000314','20000000-0000-0000-0000-000000000315']::uuid[]
),null,'shared series stores events after its maximum stage');
select is((select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and achievement_type='fellow_travelers' and notification_eligible),2,'shared notifications are limited to stage unlocks');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000311',true);
select is(jsonb_array_length((public.list_achievements('10000000-0000-0000-0000-000000000311',30,null)#>'{data,items}')->0->'events'),2,'shared RPC hides ordinary repeat events');
select is((jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000311',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "fellow_travelers")')->>'earned_at')::timestamptz,'2026-08-07 00:00:00+00'::timestamptz,'shared card date stays at the last stage unlock');
reset role;

-- Focus milestones are stored for every valid settlement, but the first
-- visible stage is not unlocked until the space reaches ten hours.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot) values
 ('40000000-0000-0000-0000-000000000320','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Milestone pre','study','completed','2026-09-01 00:00:00+00','2026-09-01 01:00:00+00','manual_end',3600,'2026-09-01 01:00:00+00','Asia/Shanghai');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','focus_milestone','focus-session:pre','2026-09-01 01:00:00+00','bronze','{}',array['20000000-0000-0000-0000-000000000311']::uuid[]
),null,'focus milestone stores a pre-threshold settlement event');
select ok(not (select notification_eligible from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='focus-session:pre'),'pre-threshold focus milestone does not notify');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot) values
 ('40000000-0000-0000-0000-000000000321','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Milestone six','study','completed','2026-09-01 01:00:00+00','2026-09-01 07:00:00+00','manual_end',21600,'2026-09-01 07:00:00+00','Asia/Shanghai'),
 ('40000000-0000-0000-0000-000000000322','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Milestone four','study','completed','2026-09-01 07:00:00+00','2026-09-01 11:00:00+00','manual_end',14400,'2026-09-01 11:00:00+00','Asia/Shanghai');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','focus_milestone','focus-session:threshold','2026-09-01 11:00:00+00','bronze','{}',array['20000000-0000-0000-0000-000000000311']::uuid[]
),null,'focus milestone stores the threshold settlement event');
select ok((select notification_eligible from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='focus-session:threshold'),'ten-hour focus milestone is the first notification stage');
select is((select tier from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='focus-session:threshold'),'bronze','ten-hour focus milestone is bronze');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000311',true);
select is(jsonb_array_length(jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000311',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "focus_milestone")')->'events'),1,'focus RPC hides pre-threshold and ordinary events');
reset role;

-- Canonical daily streak keys must not be mistaken for legacy fixed stages.
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','together_streak','together-streak-day:2026-09-02','2026-09-02 00:00:00+00','bronze',jsonb_build_object('days',1),array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312']::uuid[]
),null,'daily streak records its first stage');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','together_streak','together-streak-day:2026-09-04','2026-09-04 00:00:00+00','silver',jsonb_build_object('days',3),array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312']::uuid[]
),null,'daily streak records a stage upgrade');
select isnt(private.record_shared_achievement_event(
  '10000000-0000-0000-0000-000000000311','together_streak','together-streak-day:2026-09-05','2026-09-05 00:00:00+00','silver',jsonb_build_object('days',3),array['20000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000312']::uuid[]
),null,'daily streak stores repeats after the maximum reached stage');
select is((select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and achievement_type='together_streak' and notification_eligible),2,'daily streak notifications only cover unlock stages');

-- Two qualified members cover the entire Asia/Shanghai local day. The third
-- member contributes only ten minutes and must not become a qualifying member.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot) values
 ('40000000-0000-0000-0000-000000000311','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Flame A','study','completed','2026-08-09 16:00:00+00','2026-08-10 04:00:00+00','manual_end',21600,'2026-08-10 04:00:00+00','Asia/Shanghai'),
 ('40000000-0000-0000-0000-000000000312','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000312','20000000-0000-0000-0000-000000000312','Flame B','work','completed','2026-08-10 03:00:00+00','2026-08-10 16:00:00+00','manual_end',21600,'2026-08-10 16:00:00+00','Asia/Shanghai'),
 ('40000000-0000-0000-0000-000000000313','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000313','20000000-0000-0000-0000-000000000313','Flame short','reading','completed','2026-08-10 10:00:00+00','2026-08-10 10:10:00+00','manual_end',600,'2026-08-10 10:10:00+00','Asia/Shanghai');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000311','2026-08-09 16:00:00+00','2026-08-10 04:00:00+00'),
 ('40000000-0000-0000-0000-000000000312','2026-08-10 03:00:00+00','2026-08-10 16:00:00+00'),
 ('40000000-0000-0000-0000-000000000313','2026-08-10 10:00:00+00','2026-08-10 10:10:00+00');
select private.evaluate_living_flame_day('10000000-0000-0000-0000-000000000311','2026-08-10','2026-08-10 16:00:00+00');
select ok(exists(select 1 from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and achievement_type='living_flame' and dedupe_key='flame:2026-08-10'),'living flame accepts qualified-member union coverage of the full local day');
select is((select count(*)::integer from public.achievement_participants ap join public.achievements a on a.id=ap.achievement_id where a.space_id='10000000-0000-0000-0000-000000000311' and a.dedupe_key='flame:2026-08-10'),2,'short members are excluded from living flame provenance');
select ok((select notification_eligible from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='flame:2026-08-10'),'first living flame event is a notification event');
select ok((select (metadata->>'window_start')::timestamptz='2026-08-09 16:00:00+00' and (metadata->>'window_end')::timestamptz='2026-08-10 16:00:00+00' from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='flame:2026-08-10'),'living flame stores the exact local-day half-open boundaries');

-- A one-hour gap fails full-day coverage; evaluating the same day twice is idempotent.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot) values
 ('40000000-0000-0000-0000-000000000314','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000314','20000000-0000-0000-0000-000000000314','Gap A','study','completed','2026-08-10 16:00:00+00','2026-08-11 04:00:00+00','manual_end',21600,'2026-08-11 04:00:00+00','Asia/Shanghai'),
 ('40000000-0000-0000-0000-000000000315','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000315','20000000-0000-0000-0000-000000000315','Gap B','work','completed','2026-08-11 05:00:00+00','2026-08-11 16:00:00+00','manual_end',21600,'2026-08-11 16:00:00+00','Asia/Shanghai');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000314','2026-08-10 16:00:00+00','2026-08-11 04:00:00+00'),
 ('40000000-0000-0000-0000-000000000315','2026-08-11 05:00:00+00','2026-08-11 16:00:00+00');
select private.evaluate_living_flame_day('10000000-0000-0000-0000-000000000311','2026-08-11','2026-08-11 16:00:00+00');
select ok(not exists(select 1 from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and achievement_type='living_flame' and dedupe_key='flame:2026-08-11'),'a gap prevents living flame full-day coverage');
select private.evaluate_living_flame_day('10000000-0000-0000-0000-000000000311','2026-08-10','2026-08-10 16:00:00+00');
select is((select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and achievement_type='living_flame' and dedupe_key='flame:2026-08-10'),1,'living flame daily idempotency is unique');

-- A later local day can award the exception again, without another notification.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot) values
 ('40000000-0000-0000-0000-000000000316','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Next A','study','completed','2026-08-11 16:00:00+00','2026-08-12 04:00:00+00','manual_end',21600,'2026-08-12 04:00:00+00','Asia/Shanghai'),
 ('40000000-0000-0000-0000-000000000317','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000312','20000000-0000-0000-0000-000000000312','Next B','work','completed','2026-08-12 04:00:00+00','2026-08-12 16:00:00+00','manual_end',21600,'2026-08-12 16:00:00+00','Asia/Shanghai');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000316','2026-08-11 16:00:00+00','2026-08-12 04:00:00+00'),
 ('40000000-0000-0000-0000-000000000317','2026-08-12 04:00:00+00','2026-08-12 16:00:00+00');
select private.evaluate_living_flame_day('10000000-0000-0000-0000-000000000311','2026-08-12','2026-08-12 16:00:00+00');
select is((select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and achievement_type='living_flame'),2,'living flame repeats once on a later local day');
select ok(not (select notification_eligible from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='flame:2026-08-12'),'later living flame events are stored without notification');

-- Europe/Berlin 2026-10-25 has a 25-hour local day; midnight conversion must
-- use the following local midnight rather than adding a fixed 24 hours.
update public.spaces set timezone='Europe/Berlin' where id='10000000-0000-0000-0000-000000000311';
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at,timezone_snapshot) values
 ('40000000-0000-0000-0000-000000000318','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','DST A','study','completed','2026-10-24 22:00:00+00','2026-10-25 10:00:00+00','manual_end',21600,'2026-10-25 10:00:00+00','Asia/Shanghai'),
 ('40000000-0000-0000-0000-000000000319','10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000312','20000000-0000-0000-0000-000000000312','DST B','work','completed','2026-10-25 10:00:00+00','2026-10-25 23:00:00+00','manual_end',21600,'2026-10-25 23:00:00+00','Asia/Shanghai');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000318','2026-10-24 22:00:00+00','2026-10-25 10:00:00+00'),
 ('40000000-0000-0000-0000-000000000319','2026-10-25 10:00:00+00','2026-10-25 23:00:00+00');
select private.evaluate_living_flame_day('10000000-0000-0000-0000-000000000311','2026-10-25','2026-10-25 23:00:00+00');
select ok(exists(select 1 from public.achievements where space_id='10000000-0000-0000-0000-000000000311' and dedupe_key='flame:2026-10-25' and (metadata->>'window_end')::timestamptz='2026-10-25 23:00:00+00'),'living flame handles a DST-length local day');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000301',true);
select is(public.list_personal_achievements('10000000-0000-0000-0000-000000000301',30,null)#>>'{error,code}',null,'authenticated owner can read the RLS-safe personal RPC');
select is((select count(*)::integer from public.personal_achievements),3,'stable-principal RLS exposes only the caller personal summaries');
select is((select count(*)::integer from public.personal_achievement_awards),23,'stable-principal RLS exposes only the caller personal events');
reset role;

select ok(to_regclass('public.achievements_notification_eligible') is not null,'notification eligibility has a supporting partial index');

-- Historical compatibility aliases may remain visible in the achievement
-- list, but they must not create a second home/nav notification.
insert into public.achievements(id,space_id,achievement_type,dedupe_key,earned_at,metadata,tier,participants_recorded)
values('70000000-0000-0000-0000-000000000301','10000000-0000-0000-0000-000000000301','first_goal','historical:first-goal','2026-09-03 00:00:00+00','{}','bronze',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000301',true);
select is(public.get_nav_notifications('10000000-0000-0000-0000-000000000301')#>>'{data,shared}','false','legacy aliases do not create nav notifications');
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000301')#>>'{data,unseen_achievement}',null,'legacy aliases do not create home notifications');
reset role;

select * from finish();
rollback;
