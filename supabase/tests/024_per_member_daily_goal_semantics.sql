begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000241'),
 ('00000000-0000-0000-0000-000000000242');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000241','UTC'),
 ('00000000-0000-0000-0000-000000000242','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000241','Daily member threshold','00000000-0000-0000-0000-000000000241','UTC','daily-member-threshold');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000241','10000000-0000-0000-0000-000000000241','00000000-0000-0000-0000-000000000241','Owner','owner'),
 ('20000000-0000-0000-0000-000000000242','10000000-0000-0000-0000-000000000241','00000000-0000-0000-0000-000000000242','Member','member');
insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,resolved_at) values
 ('50000000-0000-0000-0000-000000000241','10000000-0000-0000-0000-000000000241','20000000-0000-0000-0000-000000000241','per_member_minutes','weekly',180,'accepted','2026-08-10','2026-08-10','2026-08-09');
insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status) values
 ('60000000-0000-0000-0000-000000000241','50000000-0000-0000-0000-000000000241','10000000-0000-0000-0000-000000000241','per_member_minutes','weekly',180,'2026-08-10 00:00Z','2026-08-17 00:00Z','active');
insert into public.goal_participants(goal_id,member_id) values
 ('60000000-0000-0000-0000-000000000241','20000000-0000-0000-0000-000000000241'),
 ('60000000-0000-0000-0000-000000000241','20000000-0000-0000-0000-000000000242');

with created as(
 insert into public.focus_sessions(space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason)
 select '10000000-0000-0000-0000-000000000241',u.user_id,u.member_id,'Daily threshold','completed',u.minutes*60,
   d::timestamptz+interval '1 hour',d::timestamptz+interval '1 hour'+make_interval(mins=>u.minutes),'manual_end'
 from generate_series('2026-08-10 00:00Z'::timestamptz,'2026-08-16 00:00Z'::timestamptz,interval '1 day') d
 cross join lateral(values
   ('00000000-0000-0000-0000-000000000241'::uuid,'20000000-0000-0000-0000-000000000241'::uuid,180),
   ('00000000-0000-0000-0000-000000000242'::uuid,'20000000-0000-0000-0000-000000000242'::uuid,case when d::date='2026-08-16' then 120 else 180 end)
 ) u(user_id,member_id,minutes)
 returning id,started_at,completed_at
) insert into public.focus_segments(session_id,started_at,ended_at)
select id,started_at,completed_at from created;

select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{required_days}','7','weekly per-member target requires all seven local days');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{members,0,completed_days}','6','member missing one day has only six completed days');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{members,1,completed_days}','7','member meeting every daily threshold has seven completed days');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{completed}','false','weekly target does not pass when one member misses one day');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{members,0,current_day_credited_minutes}','120','daily progress reports the final local day independently');

with created as(
 insert into public.focus_sessions(space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason)
 values('10000000-0000-0000-0000-000000000241','00000000-0000-0000-0000-000000000242','20000000-0000-0000-0000-000000000242','Finish final day','completed',3600,'2026-08-16 04:00Z','2026-08-16 05:00Z','manual_end')
 returning id,started_at,completed_at
) insert into public.focus_segments(session_id,started_at,ended_at) select id,started_at,completed_at from created;

select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{members,0,completed_days}','7','the missing member reaches seven completed days after the final daily hour');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{members,0,current_day_credited_minutes}','180','same-day sessions add only within that local day');
select is(public.goal_progress_json('60000000-0000-0000-0000-000000000241','2026-08-17 00:00Z')#>>'{completed}','true','weekly target passes only after every member meets every daily threshold');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000241',true);
select is(public.propose_goal('10000000-0000-0000-0000-000000000241','per_member_minutes','weekly',721,'30000000-0000-0000-0000-000000000241')#>>'{error,code}','INVALID_TARGET_VALUE','per-member daily threshold rejects values above the daily maximum');

select * from finish();
rollback;
