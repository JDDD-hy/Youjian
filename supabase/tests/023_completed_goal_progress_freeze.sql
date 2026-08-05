begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

insert into auth.users(id) values ('00000000-0000-0000-0000-000000000231'),('00000000-0000-0000-0000-000000000232');
insert into public.profiles(id,timezone) values ('00000000-0000-0000-0000-000000000231','UTC'),('00000000-0000-0000-0000-000000000232','UTC');
insert into public.spaces(id,name,owner_id,timezone,daily_checkin_target_minutes,invite_token_hash) values ('10000000-0000-0000-0000-000000000231','Frozen history','00000000-0000-0000-0000-000000000231','UTC',30,'frozen-history');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000231','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','Owner','owner'),
 ('20000000-0000-0000-0000-000000000232','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232','Member','member');
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at) values
  ('50000000-0000-0000-0000-000000000231','10000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','group_total_minutes','daily',30,'accepted','2026-08-12','2026-08-10','2026-08-09','2026-08-09'),
  ('50000000-0000-0000-0000-000000000232','10000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','per_member_minutes','daily',10,'accepted','2026-08-12','2026-08-10','2026-08-09','2026-08-09'),
  ('50000000-0000-0000-0000-000000000233','10000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','group_total_minutes','daily',30,'accepted','2026-08-12','2026-08-10','2026-08-09','2026-08-09');
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status,completed_at) values
 ('60000000-0000-0000-0000-000000000231','50000000-0000-0000-0000-000000000231','10000000-0000-0000-0000-000000000231','group_total_minutes','daily',30,'2026-08-10 00:00Z','2026-08-12 00:00Z','completed','2026-08-10 00:30Z'),
  ('60000000-0000-0000-0000-000000000232','50000000-0000-0000-0000-000000000233','10000000-0000-0000-0000-000000000231','group_total_minutes','daily',30,'2026-08-10 00:00Z','2026-08-12 00:00Z','active',null),
 ('60000000-0000-0000-0000-000000000233','50000000-0000-0000-0000-000000000232','10000000-0000-0000-0000-000000000231','per_member_minutes','daily',10,'2026-08-10 00:00Z','2026-08-12 00:00Z','completed','2026-08-10 00:30Z');
insert into public.goal_participants(goal_id,member_id) values
 ('60000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231'),('60000000-0000-0000-0000-000000000232','20000000-0000-0000-0000-000000000231'),('60000000-0000-0000-0000-000000000233','20000000-0000-0000-0000-000000000231');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason) values
 ('40000000-0000-0000-0000-000000000231','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','Reached target','completed',1800,'2026-08-10 00:00Z','2026-08-10 00:30Z','manual_end'),
 ('40000000-0000-0000-0000-000000000232','10000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000231','20000000-0000-0000-0000-000000000231','After completion','completed',1800,'2026-08-10 01:00Z','2026-08-10 01:30Z','manual_end');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000231','2026-08-10 00:00Z','2026-08-10 00:30Z'),('40000000-0000-0000-0000-000000000232','2026-08-10 01:00Z','2026-08-10 01:30Z');

select is(public.goal_progress_json('60000000-0000-0000-0000-000000000231','2026-08-11 00:00Z')#>>'{credited_value}','30','completed group goal freezes at completed_at');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000231','2026-08-11 00:00Z')#>>'{completed}','true','frozen group goal remains completed');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000232','2026-08-11 00:00Z')#>>'{credited_value}','60','active goal still includes later focus');
select * from finish();
rollback;
