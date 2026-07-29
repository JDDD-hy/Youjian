begin;
create extension if not exists pgtap with schema extensions;
select plan(30);
insert into auth.users(id) values('00000000-0000-0000-0000-000000000071'),('00000000-0000-0000-0000-000000000072'),('00000000-0000-0000-0000-000000000073');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000071','Asia/Shanghai'),('00000000-0000-0000-0000-000000000072','Europe/Paris'),('00000000-0000-0000-0000-000000000073','UTC');
insert into public.spaces(id,name,owner_id,timezone,member_limit,invite_token_hash) values('10000000-0000-0000-0000-000000000071','Goals','00000000-0000-0000-0000-000000000071','Asia/Shanghai',4,'goals');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000071','10000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000071','Owner','owner'),
 ('20000000-0000-0000-0000-000000000072','10000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000072','Friend','member');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select is(public.propose_goal('10000000-0000-0000-0000-000000000071','group_total_minutes','weekly',10,'30000000-0000-0000-0000-000000000071')#>>'{data,proposal,accepted_vote_count}','1','proposer auto-accepts');
select is((select count(*)::int from public.goal_proposal_members gpm join public.goal_proposals gp on gp.id=gpm.proposal_id where gp.space_id='10000000-0000-0000-0000-000000000071'),2,'proposal freezes voter snapshot');
select is(public.get_goals_snapshot('10000000-0000-0000-0000-000000000071')#>>'{data,pending_proposals,0,required_vote_count}','2','snapshot reports required votes');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000072',true);
select is(public.vote_goal_proposal((select id from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000071' and goal_type='group_total_minutes'),'accepted','30000000-0000-0000-0000-000000000072')#>>'{data,proposal,status}','accepted','last accept resolves proposal');
select is((select status::text from public.goals where space_id='10000000-0000-0000-0000-000000000071' and goal_type='group_total_minutes'),'scheduled','accepted proposal creates scheduled goal');
select is((select count(*)::int from public.goal_participants gp join public.goals g on g.id=gp.goal_id where g.space_id='10000000-0000-0000-0000-000000000071'),2,'goal participant snapshot matches voters');
select is(public.vote_goal_proposal((select id from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000071' and goal_type='group_total_minutes'),'accepted','30000000-0000-0000-0000-000000000072'),
 (select result from public.focus_commands where actor_id='00000000-0000-0000-0000-000000000072' and idempotency_key='30000000-0000-0000-0000-000000000072'),'vote retry is idempotent');
select is(public.vote_goal_proposal((select id from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000071' and goal_type='group_total_minutes'),'rejected','30000000-0000-0000-0000-000000000073')#>>'{error,code}','PROPOSAL_NOT_PENDING','resolved proposal cannot be changed');

insert into public.space_members(id,space_id,user_id,display_name,role) values('20000000-0000-0000-0000-000000000073','10000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000073','Third','member');
select is((select count(*)::int from public.goal_participants gp join public.goals g on g.id=gp.goal_id where g.space_id='10000000-0000-0000-0000-000000000071'),2,'later join does not change participant snapshot');
select ok(extract(epoch from upper(public.next_goal_period('Europe/Paris','daily','2026-03-28 12:00Z'))-lower(public.next_goal_period('Europe/Paris','daily','2026-03-28 12:00Z'))) in (82800,86400),'next local daily period honors DST');

update public.goals set starts_at=now()-interval '1 hour',ends_at=now()+interval '1 hour',status='active' where space_id='10000000-0000-0000-0000-000000000071' and goal_type='group_total_minutes';
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason,last_seen_at) values
 ('40000000-0000-0000-0000-000000000071','10000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000071','20000000-0000-0000-0000-000000000071','Goal A','completed',300,now()-interval '10 min',now()-interval '5 min','manual_end',now()-interval '5 min'),
 ('40000000-0000-0000-0000-000000000072','10000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000072','20000000-0000-0000-0000-000000000072','Goal B','completed',300,now()-interval '10 min',now()-interval '5 min','manual_end',now()-interval '5 min');
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000071',now()-interval '10 min',now()-interval '5 min'),('40000000-0000-0000-0000-000000000072',now()-interval '10 min',now()-interval '5 min');
select lives_ok($$select public.run_goal_maintenance(now())$$,'goal maintenance evaluates active goal');
select is((select status::text from public.goals where space_id='10000000-0000-0000-0000-000000000071' and goal_type='group_total_minutes'),'completed','group goal completes at target');
select is((select count(*)::int from public.achievements where space_id='10000000-0000-0000-0000-000000000071' and achievement_type='first_goal'),1,'completed goal grants first-goal achievement');
select lives_ok($$select public.run_goal_maintenance(now())$$,'achievement maintenance is rerunnable');
select is((select count(*)::int from public.achievements where space_id='10000000-0000-0000-0000-000000000071' and achievement_type='first_goal'),1,'achievement dedupe prevents duplicate award');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select is(public.mark_achievement_seen((select id from public.achievements where space_id='10000000-0000-0000-0000-000000000071' and achievement_type='first_goal'),'30000000-0000-0000-0000-000000000074')#>>'{data,seen}','true','owner marks achievement seen');
select is((select count(*)::int from public.achievement_reads ar join public.achievements a on a.id=ar.achievement_id where a.space_id='10000000-0000-0000-0000-000000000071'),1,'seen state writes one member relationship');
select ok(not ((public.list_achievements('10000000-0000-0000-0000-000000000071',30,null)#>'{data,items,0}') ? 'dedupe_key'),'achievement API hides dedupe key');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000072',true);
select is(public.list_achievements('10000000-0000-0000-0000-000000000071',30,null)#>>'{data,items,0,seen}','false','seen state is independent per member');
select is(public.get_space_settings('10000000-0000-0000-0000-000000000071')#>>'{data,owner_actions,can_disable_members}','false','ordinary member has no owner actions');
select is(public.disable_member('10000000-0000-0000-0000-000000000071','20000000-0000-0000-0000-000000000073','30000000-0000-0000-0000-000000000075')#>>'{error,code}','NOT_SPACE_OWNER','ordinary member cannot disable member');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select is(public.propose_goal('10000000-0000-0000-0000-000000000071','per_member_minutes','daily',30,'30000000-0000-0000-0000-000000000076')#>>'{data,proposal,status}','pending','second proposal created');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000072',true);
select is(public.vote_goal_proposal((select id from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000071' and status='pending' and goal_type='per_member_minutes'),'accepted','30000000-0000-0000-0000-000000000077')#>>'{data,proposal,status}','pending','one pending member remains');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000073',true);
select lives_ok($$select public.start_focus('10000000-0000-0000-0000-000000000071','Before disable','work','30000000-0000-0000-0000-000000000078')$$,'target member starts focus');
update public.focus_sessions set active_segment_started_at=now()-interval '600 seconds' where task_name='Before disable'; update public.focus_segments set started_at=now()-interval '600 seconds' where ended_at is null;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000071',true);
select is(jsonb_array_length(public.disable_member('10000000-0000-0000-0000-000000000071','20000000-0000-0000-0000-000000000073','30000000-0000-0000-0000-000000000079')#>'{data,resolved_proposals}'),1,'disable recomputes pending proposal');
select is((select completion_reason::text from public.focus_sessions where task_name='Before disable'),'member_disabled','disable settles active session with authoritative reason');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Before disable'),600,'disable preserves focused duration');
select is((select count(*)::int from public.goal_participants gp join public.goals g on g.id=gp.goal_id where g.source_proposal_id=(select id from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000071' and goal_type='per_member_minutes')),2,'resolved proposal snapshots remaining members');
select is(public.get_space_settings('10000000-0000-0000-0000-000000000071')#>>'{data,owner_actions,can_disable_members}','true','owner receives management actions');
select is(jsonb_array_length(public.get_space_settings('10000000-0000-0000-0000-000000000071')#>'{data,members}'),3,'settings retain disabled member history');
select * from finish(); rollback;
