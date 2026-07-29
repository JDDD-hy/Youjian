-- Deterministic, synthetic local-only fixtures. These identities are not
-- login credentials and contain no copied production data.
begin;
insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_anonymous)
values
 ('90000000-0000-0000-0000-000000000001','authenticated','authenticated','{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now(),true),
 ('90000000-0000-0000-0000-000000000002','authenticated','authenticated','{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now(),true),
 ('90000000-0000-0000-0000-000000000003','authenticated','authenticated','{"provider":"anonymous","providers":["anonymous"]}','{}',now(),now(),true);

insert into public.profiles(id,timezone) values
 ('90000000-0000-0000-0000-000000000001','Asia/Shanghai'),
 ('90000000-0000-0000-0000-000000000002','Europe/Paris'),
 ('90000000-0000-0000-0000-000000000003','America/New_York');

insert into public.spaces(id,name,owner_id,timezone,member_limit,daily_checkin_target_minutes,invite_token_hash)
values('90000000-0000-0000-0000-000000000010','我们的友间','90000000-0000-0000-0000-000000000001','Asia/Shanghai',6,60,repeat('9',64));

insert into public.space_members(id,space_id,user_id,display_name,role,status,joined_at,disabled_at,disabled_by)
values
 ('90000000-0000-0000-0000-000000000011','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000001','测试房主','owner','active',now()-interval '30 days',null,null),
 ('90000000-0000-0000-0000-000000000012','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000002','测试成员','member','active',now()-interval '20 days',null,null),
 ('90000000-0000-0000-0000-000000000013','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000003','已停用成员','member','disabled',now()-interval '15 days',now()-interval '2 days','90000000-0000-0000-0000-000000000001');

insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,accumulated_focus_seconds,active_segment_started_at,paused_at,started_at,completed_at,completion_reason,last_seen_at,unconfirmed_connection_seconds)
values
 ('91000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000011','测试阅读任务','reading','focusing',0,now()-interval '36 minutes',null,now()-interval '36 minutes',null,null,now()-interval '3 minutes',0),
 ('91000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000012','测试暂停任务','study','paused',1500,null,now()-interval '5 minutes',now()-interval '30 minutes',null,null,now()-interval '5 minutes',0),
 ('91000000-0000-0000-0000-000000000003','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000011','测试跨午夜任务','work','completed',1800,null,null,(date_trunc('day',timezone('Asia/Shanghai',now())) at time zone 'Asia/Shanghai')-interval '10 minutes',(date_trunc('day',timezone('Asia/Shanghai',now())) at time zone 'Asia/Shanghai')+interval '20 minutes','manual_end',now()-interval '1 day',0),
 ('91000000-0000-0000-0000-000000000004','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000012','测试短时任务','other','discarded',299,null,null,now()-interval '2 days 5 minutes',now()-interval '2 days','manual_end',now()-interval '2 days',0);

insert into public.focus_segments(session_id,started_at,ended_at) values
 ('91000000-0000-0000-0000-000000000001',now()-interval '36 minutes',null),
 ('91000000-0000-0000-0000-000000000002',now()-interval '30 minutes',now()-interval '5 minutes'),
 ('91000000-0000-0000-0000-000000000003',(date_trunc('day',timezone('Asia/Shanghai',now())) at time zone 'Asia/Shanghai')-interval '10 minutes',(date_trunc('day',timezone('Asia/Shanghai',now())) at time zone 'Asia/Shanghai')+interval '20 minutes'),
 ('91000000-0000-0000-0000-000000000004',now()-interval '2 days 5 minutes',now()-interval '2 days 1 second');

insert into public.focus_events(session_id,actor_id,event_type,occurred_at) values
 ('91000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','started',now()-interval '36 minutes'),
 ('91000000-0000-0000-0000-000000000001',null,'connection_unconfirmed',now()-interval '2 minutes'),
 ('91000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000002','started',now()-interval '30 minutes'),
 ('91000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000002','paused',now()-interval '5 minutes'),
 ('91000000-0000-0000-0000-000000000003','90000000-0000-0000-0000-000000000001','completed',(date_trunc('day',timezone('Asia/Shanghai',now())) at time zone 'Asia/Shanghai')+interval '20 minutes'),
 ('91000000-0000-0000-0000-000000000004','90000000-0000-0000-0000-000000000002','completed',now()-interval '2 days');

insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at)
values('91000000-0000-0000-0000-000000000001',now()-interval '2 minutes',now()-interval '3 minutes');

insert into public.goal_proposals(id,space_id,proposer_member_id,goal_type,period_type,target_value,status,expires_at,effective_period_start,created_at,resolved_at)
values
 ('92000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000011','shared_checkin_days','weekly',3,'pending',now()+interval '24 hours',date_trunc('week',now())+interval '1 week',now(),null),
 ('92000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000011','group_total_minutes','daily',600,'accepted',now()+interval '24 hours',date_trunc('day',now())+interval '1 day',now()-interval '1 hour',now()-interval '30 minutes'),
 ('92000000-0000-0000-0000-000000000003','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000011','per_member_minutes','weekly',300,'accepted',now()-interval '1 day',date_trunc('week',now()),now()-interval '3 days',now()-interval '2 days'),
 ('92000000-0000-0000-0000-000000000004','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000011','group_total_minutes','daily',30,'accepted',now()-interval '2 days',date_trunc('day',now())-interval '1 day',now()-interval '4 days',now()-interval '3 days'),
 ('92000000-0000-0000-0000-000000000005','90000000-0000-0000-0000-000000000010','90000000-0000-0000-0000-000000000011','shared_checkin_days','weekly',7,'accepted',now()-interval '8 days',date_trunc('week',now())-interval '1 week',now()-interval '10 days',now()-interval '9 days');

insert into public.goal_proposal_members(proposal_id,member_id,vote,voted_at)
select p.id,m.id,case when p.status='pending' and m.role='member' then null else 'accepted'::public.goal_vote end,
 case when p.status='pending' and m.role='member' then null else coalesce(p.resolved_at,p.created_at) end
from public.goal_proposals p
join public.space_members m on m.space_id=p.space_id and m.status='active'
where p.id::text like '92000000-%';

insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status,completed_at)
values
 ('93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000010','group_total_minutes','daily',600,date_trunc('day',now())+interval '1 day',date_trunc('day',now())+interval '2 days','scheduled',null),
 ('93000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000003','90000000-0000-0000-0000-000000000010','per_member_minutes','weekly',300,date_trunc('week',now()),date_trunc('week',now())+interval '1 week','active',null),
 ('93000000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000004','90000000-0000-0000-0000-000000000010','group_total_minutes','daily',30,date_trunc('day',now())-interval '1 day',date_trunc('day',now()),'completed',date_trunc('day',now())),
 ('93000000-0000-0000-0000-000000000005','92000000-0000-0000-0000-000000000005','90000000-0000-0000-0000-000000000010','shared_checkin_days','weekly',7,date_trunc('week',now())-interval '1 week',date_trunc('week',now()),'failed',date_trunc('week',now()));

insert into public.goal_participants(goal_id,member_id)
select g.id,m.id from public.goals g join public.space_members m on m.space_id=g.space_id and m.status='active'
where g.id::text like '93000000-%';

insert into public.achievements(id,space_id,achievement_type,dedupe_key,earned_at,metadata) values
 ('94000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000010','first_goal','seed:first-goal',now()-interval '1 day','{"synthetic":true}'),
 ('94000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000010','three_day_together','seed:three-days',now()-interval '2 hours','{"synthetic":true}');

commit;
