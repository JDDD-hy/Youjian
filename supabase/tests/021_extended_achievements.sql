begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

update public.achievement_rule_versions set enabled_at='2026-08-01 00:00:00+00' where version='extended-v1';
insert into auth.users(id) values('00000000-0000-0000-0000-000000000211');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000211','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,daily_checkin_target_minutes,invite_token_hash)
values('10000000-0000-0000-0000-000000000211','Extended achievements','00000000-0000-0000-0000-000000000211','Asia/Shanghai',30,'extended-achievements');
insert into public.space_members(id,space_id,user_id,display_name,role)
values('20000000-0000-0000-0000-000000000211','10000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000211','Owner','owner');

-- 05:00 local, exactly 60 minutes, and no pause.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000211','10000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000211','20000000-0000-0000-0000-000000000211','Dawn','study','focusing','2026-08-01 21:00:00+00','2026-08-01 21:00:00+00','2026-08-01 21:00:00+00');
insert into public.focus_segments(session_id,started_at,ended_at)
values('40000000-0000-0000-0000-000000000211','2026-08-01 21:00:00+00','2026-08-01 22:00:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=3600,active_segment_started_at=null,completed_at='2026-08-01 22:00:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000211';
select ok(exists(select 1 from public.personal_achievements where achievement_type='dawn_walker' and tier='gold'),'05:00 and exactly 60 minutes awards dawn walker');
select ok(exists(select 1 from public.personal_achievements where achievement_type='unbroken_focus' and tier='gold'),'a never-paused 60-minute session awards unbroken focus');
select ok(exists(select 1 from public.personal_achievements where achievement_type='solo_focus'),'the same session may also award solo focus');

-- Three same-day, same-day-completed sessions in three final categories.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at) values
 ('40000000-0000-0000-0000-000000000212','10000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000211','20000000-0000-0000-0000-000000000211','Study','study','completed','2026-08-03 01:00:00+00','2026-08-03 01:30:00+00','manual_end',1800,'2026-08-03 01:30:00+00'),
 ('40000000-0000-0000-0000-000000000213','10000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000211','20000000-0000-0000-0000-000000000211','Work','work','completed','2026-08-03 02:00:00+00','2026-08-03 02:30:00+00','manual_end',1800,'2026-08-03 02:30:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000212','2026-08-03 01:00:00+00','2026-08-03 01:30:00+00'),
 ('40000000-0000-0000-0000-000000000213','2026-08-03 02:00:00+00','2026-08-03 02:30:00+00');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000214','10000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000211','20000000-0000-0000-0000-000000000211','Other','other','focusing','2026-08-03 03:00:00+00','2026-08-03 03:00:00+00','2026-08-03 03:00:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000214','2026-08-03 03:00:00+00','2026-08-03 03:30:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=1800,active_segment_started_at=null,completed_at='2026-08-03 03:30:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000214';
select ok(exists(select 1 from public.personal_achievements where achievement_type='double_focus'),'two qualifying sessions award double focus');
select ok(exists(select 1 from public.personal_achievements where achievement_type='triple_focus'),'three qualifying sessions award triple focus');
select ok(exists(select 1 from public.personal_achievements where achievement_type='three_categories'),'three final categories, including other, award three categories');

select ok(private.record_personal_achievement_event('00000000-0000-0000-0000-000000000211','promise_keeper','10000000-0000-0000-0000-000000000211','40000000-0000-0000-0000-000000000212','promise-30','2026-08-04','2026-08-04 12:00:00+00',jsonb_build_object('stage_days',30)),'the 30-day promise stage records');
select is((select tier from public.personal_achievements where achievement_type='promise_keeper'),'diamond','the fourth series stage is diamond');
select ok(private.record_personal_achievement_event('00000000-0000-0000-0000-000000000211','promise_keeper','10000000-0000-0000-0000-000000000211','40000000-0000-0000-0000-000000000213','promise-reset','2026-08-05','2026-08-05 12:00:00+00',jsonb_build_object('stage_days',1)),'a later restarted promise series still counts');
select is((select tier from public.personal_achievements where achievement_type='promise_keeper'),'diamond','a restarted series never downgrades its highest stage');

select isnt(private.record_shared_achievement_event('10000000-0000-0000-0000-000000000211','chance_encounter','encounter:test','2026-08-05 13:00:00+00','gold','{}',array['20000000-0000-0000-0000-000000000211']::uuid[]),null,'shared event recorder creates an event');
select is(private.record_shared_achievement_event('10000000-0000-0000-0000-000000000211','chance_encounter','encounter:test','2026-08-05 13:00:00+00','gold','{}',array['20000000-0000-0000-0000-000000000211']::uuid[]),null,'shared event recorder is idempotent');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000211',true);
select is(public.get_nav_notifications('10000000-0000-0000-0000-000000000211')#>>'{data,personal}','true','new personal achievements set the navigation dot');
select is(public.mark_achievement_tab_seen('10000000-0000-0000-0000-000000000211','personal')#>>'{data,seen}','true','viewing the personal tab persists its read watermark');

select * from finish();
rollback;
