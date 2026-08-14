begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

update public.achievement_rule_versions set enabled_at='2026-08-01 00:00:00+00' where version='extended-v1';
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000231'),
 ('00000000-0000-0000-0000-000000000232'),
 ('00000000-0000-0000-0000-000000000233');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000231','Asia/Shanghai'),
 ('00000000-0000-0000-0000-000000000232','UTC'),
 ('00000000-0000-0000-0000-000000000233','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000231','Timezone and flame','00000000-0000-0000-0000-000000000231','UTC','timezone-flame');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000231','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','Owner','owner'),
 ('20000000-0000-0000-0000-000000000232','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','Second','member'),
 ('20000000-0000-0000-0000-000000000233','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000233','Third','member');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000231',true);
select is(public.start_focus('10000000-0000-0000-0000-000000000231','Paris work','study','Europe/Paris','30000000-0000-0000-0000-000000000231')#>>'{data,session,status}','focusing','start accepts the current browser IANA timezone');
select is(public.start_focus('10000000-0000-0000-0000-000000000231','Invalid','study','Mars/Olympus','30000000-0000-0000-0000-000000000232')#>>'{error,code}','INVALID_TIMEZONE','start rejects a non-IANA timezone');
reset role;
select is((select timezone from public.profiles where id='00000000-0000-0000-0000-000000000231'),'Europe/Paris','start refreshes the profile timezone after travel');
select is((select timezone_snapshot from public.focus_sessions where task_name='Paris work'),'Europe/Paris','the session freezes the focus-location timezone');
select is(public.session_json((select id from public.focus_sessions where task_name='Paris work'))->>'timezone_snapshot','Europe/Paris','session responses expose the timezone snapshot');
update public.focus_sessions set status='discarded',active_segment_started_at=null,completed_at=now(),completion_reason='manual_end' where task_name='Paris work';
update public.profiles set timezone='UTC' where id='00000000-0000-0000-0000-000000000231';

-- Two qualifying members cover the complete UTC local day. Their segments
-- meet at noon, so overlap is not required and the union has no gap.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at) values
 ('40000000-0000-0000-0000-000000000231','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','Flame one','study','completed','2026-08-05 00:00:00+00','2026-08-05 06:00:00+00','manual_end',21600,'2026-08-05 06:00:00+00'),
 ('40000000-0000-0000-0000-000000000232','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','Flame one continued','study','completed','2026-08-05 06:00:00+00','2026-08-05 12:00:00+00','manual_end',21600,'2026-08-05 12:00:00+00');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000233','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','20000000-0000-0000-0000-000000000232','Flame two','work','focusing','2026-08-05 06:10:00+00','2026-08-05 06:10:00+00','2026-08-05 06:10:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000231','2026-08-05 00:00:00+00','2026-08-05 06:00:00+00'),
 ('40000000-0000-0000-0000-000000000232','2026-08-05 06:00:00+00','2026-08-05 12:00:00+00'),
 ('40000000-0000-0000-0000-000000000233','2026-08-05 06:10:00+00','2026-08-05 12:10:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=21600,active_segment_started_at=null,completed_at='2026-08-05 12:10:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000233';
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000234','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','20000000-0000-0000-0000-000000000232','Flame two continued','work','focusing','2026-08-05 12:10:00+00','2026-08-05 12:10:00+00','2026-08-05 12:10:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000234','2026-08-05 12:10:00+00','2026-08-05 18:10:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=21600,active_segment_started_at=null,completed_at='2026-08-05 18:10:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000234';
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000238','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','20000000-0000-0000-0000-000000000232','Flame two final','work','focusing','2026-08-05 18:10:00+00','2026-08-05 18:10:00+00','2026-08-05 18:10:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000238','2026-08-05 18:10:00+00','2026-08-06 00:10:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=21600,active_segment_started_at=null,completed_at='2026-08-06 00:10:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000238';

select ok(exists(select 1 from public.achievements where space_id='10000000-0000-0000-0000-000000000231' and achievement_type='living_flame' and metadata->>'local_date'='2026-08-05'),'the qualifying-member union covers the complete local day');
select is((select count(*)::integer from public.achievement_participants ap join public.achievements a on a.id=ap.achievement_id where a.achievement_type='living_flame' and a.space_id='10000000-0000-0000-0000-000000000231'),2,'living flame records the two qualifying members');
select is((select tier from public.achievements where achievement_type='living_flame' and space_id='10000000-0000-0000-0000-000000000231'),'gold','living flame remains fixed gold');

-- A->B and B->A are the same unordered member pair on the same space day.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at)
values('40000000-0000-0000-0000-000000000235','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','Relay A to B','study','completed','2026-08-06 05:00:00+00','2026-08-06 05:30:00+00','manual_end',1800,'2026-08-06 05:30:00+00');
insert into public.focus_segments(session_id,started_at,ended_at)
values('40000000-0000-0000-0000-000000000235','2026-08-06 05:00:00+00','2026-08-06 05:30:00+00');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000236','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','20000000-0000-0000-0000-000000000232','Relay B receives','work','focusing','2026-08-06 05:34:00+00','2026-08-06 05:34:00+00','2026-08-06 05:34:00+00');
insert into public.focus_segments(session_id,started_at,ended_at)
values('40000000-0000-0000-0000-000000000236','2026-08-06 05:34:00+00','2026-08-06 06:04:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=1800,active_segment_started_at=null,completed_at='2026-08-06 06:04:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000236';
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000237','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','Relay A receives','reading','focusing','2026-08-06 06:08:00+00','2026-08-06 06:08:00+00','2026-08-06 06:08:00+00');
insert into public.focus_segments(session_id,started_at,ended_at)
values('40000000-0000-0000-0000-000000000237','2026-08-06 06:08:00+00','2026-08-06 06:38:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=1800,active_segment_started_at=null,completed_at='2026-08-06 06:38:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000237';
select is((select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000231' and achievement_type='focus_relay' and metadata->>'local_date'='2026-08-06'),1,'opposite relay directions for the same pair count only once per space day');

select * from finish();
rollback;
