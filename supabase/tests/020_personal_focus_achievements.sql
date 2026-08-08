begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000201'),
 ('00000000-0000-0000-0000-000000000202');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000201','Asia/Shanghai'),
 ('00000000-0000-0000-0000-000000000202','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,daily_checkin_target_minutes,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000201','Achievement one','00000000-0000-0000-0000-000000000201','Asia/Shanghai',30,'achievement-one'),
 ('10000000-0000-0000-0000-000000000202','Achievement two','00000000-0000-0000-0000-000000000201','Asia/Shanghai',30,'achievement-two');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000201','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000201','Owner','owner'),
 ('20000000-0000-0000-0000-000000000202','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000202','Friend','member'),
 ('20000000-0000-0000-0000-000000000203','10000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000201','Owner','owner');

-- 23:00 local start, one hour effective focus, and a local-midnight crossing.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000201','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000201','20000000-0000-0000-0000-000000000201','Night boundary','study','focusing','2026-08-04 15:00:00+00','2026-08-04 15:00:00+00','2026-08-04 15:00:00+00');
insert into public.focus_segments(session_id,started_at,ended_at)
values('40000000-0000-0000-0000-000000000201','2026-08-04 15:00:00+00','2026-08-04 16:00:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=3600,active_segment_started_at=null,
 completed_at='2026-08-04 16:00:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000201';
select is((select timezone_snapshot from public.focus_sessions where id='40000000-0000-0000-0000-000000000201'),'Asia/Shanghai','focus start snapshots the user timezone');
select is((select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='night_owl'),'gold','23:00 crossing midnight awards fixed-gold night owl');
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus'),1,'an overlap-free hour awards solo focus');

-- 22:59 is outside the night rule, even when it crosses midnight.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at)
values('40000000-0000-0000-0000-000000000202','10000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000201','20000000-0000-0000-0000-000000000203','Too early','study','focusing','2026-08-05 14:59:00+00','2026-08-05 14:59:00+00','2026-08-05 14:59:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000202','2026-08-05 14:59:00+00','2026-08-05 16:00:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=3660,active_segment_started_at=null,completed_at='2026-08-05 16:00:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000202';
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='night_owl'),1,'22:59 does not award night owl');
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus'),2,'personal counts accumulate across spaces');

-- An actual focused overlap invalidates solo focus.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at) values
 ('40000000-0000-0000-0000-000000000203','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000202','20000000-0000-0000-0000-000000000202','Overlap','work','completed','2026-08-06 02:30:00+00','2026-08-06 02:45:00+00','manual_end',900,'2026-08-06 02:45:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000203','2026-08-06 02:30:00+00','2026-08-06 02:45:00+00');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000204','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000201','20000000-0000-0000-0000-000000000201','Candidate','study','focusing','2026-08-06 02:00:00+00','2026-08-06 02:00:00+00','2026-08-06 02:00:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000204','2026-08-06 02:00:00+00','2026-08-06 03:00:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=3600,active_segment_started_at=null,completed_at='2026-08-06 03:00:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000204';
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus'),2,'any focused overlap permanently invalidates the candidate session');

-- Other focus entirely inside the candidate pause does not overlap its effective segments.
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,started_at,completed_at,completion_reason,accumulated_focus_seconds,last_seen_at) values
 ('40000000-0000-0000-0000-000000000205','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000202','20000000-0000-0000-0000-000000000202','Pause gap','work','completed','2026-08-07 02:35:00+00','2026-08-07 02:45:00+00','manual_end',600,'2026-08-07 02:45:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000205','2026-08-07 02:35:00+00','2026-08-07 02:45:00+00');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at) values
 ('40000000-0000-0000-0000-000000000206','10000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000201','20000000-0000-0000-0000-000000000201','Paused candidate','study','focusing','2026-08-07 02:50:00+00','2026-08-07 02:00:00+00','2026-08-07 02:50:00+00');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000206','2026-08-07 02:00:00+00','2026-08-07 02:30:00+00'),
 ('40000000-0000-0000-0000-000000000206','2026-08-07 02:50:00+00','2026-08-07 03:20:00+00');
update public.focus_sessions set status='completed',accumulated_focus_seconds=3600,active_segment_started_at=null,completed_at='2026-08-07 03:20:00+00',completion_reason='manual_end' where id='40000000-0000-0000-0000-000000000206';
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus'),3,'focus during a candidate pause does not invalidate solo focus');

select is(private.record_personal_achievement('00000000-0000-0000-0000-000000000201','solo_focus','10000000-0000-0000-0000-000000000201','40000000-0000-0000-0000-000000000206','2026-08-07 03:20:00+00'),false,'the same session cannot count twice');
select is((select count(*)::integer from public.personal_achievement_awards where source_session_id='40000000-0000-0000-0000-000000000206' and achievement_type='solo_focus'),1,'per-session award detail remains unique');

-- Exercise tier transitions without constructing another seventeen hour-long fixtures.
select ok(private.record_personal_achievement('00000000-0000-0000-0000-000000000201','solo_focus','10000000-0000-0000-0000-000000000201','40000000-0000-0000-0000-000000000203','2026-08-08 00:00:00+00'),'a different session can increment solo focus');
select ok(private.record_personal_achievement('00000000-0000-0000-0000-000000000201','solo_focus','10000000-0000-0000-0000-000000000201','40000000-0000-0000-0000-000000000204','2026-08-09 00:00:00+00'),'fifth distinct solo award is accepted');
select is((select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus'),'silver','five solo awards upgrade to silver');
update public.personal_achievements set count=19,tier='silver' where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus';
select ok(private.record_personal_achievement('00000000-0000-0000-0000-000000000201','solo_focus','10000000-0000-0000-0000-000000000201','40000000-0000-0000-0000-000000000205','2026-08-10 00:00:00+00'),'twentieth distinct solo award is accepted');
select is((select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000201' and achievement_type='solo_focus'),'gold','twenty solo awards upgrade to gold');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select is(public.list_personal_achievements('10000000-0000-0000-0000-000000000201',30,null)#>>'{data,items,0,tier}','gold','personal achievement RPC returns the global summary');
select is((select count(*)::integer from public.personal_achievements),2,'RLS lets the owner read only their own earned summaries');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000202',true);
select is((select count(*)::integer from public.personal_achievements),0,'RLS hides another user personal achievements');
select is(public.list_personal_achievements('10000000-0000-0000-0000-000000000202',30,null)#>>'{error,code}','SPACE_ACCESS_DENIED','personal list still requires access to the route space');

select * from finish();
rollback;
