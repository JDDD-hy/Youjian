begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000181'),
 ('00000000-0000-0000-0000-000000000182'),
 ('00000000-0000-0000-0000-000000000183');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000181','Asia/Shanghai'),
 ('00000000-0000-0000-0000-000000000182','Asia/Shanghai'),
 ('00000000-0000-0000-0000-000000000183','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,member_limit,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000181','Original','00000000-0000-0000-0000-000000000181','Asia/Shanghai',3,'mutable-space');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000181','10000000-0000-0000-0000-000000000181','00000000-0000-0000-0000-000000000181','Owner','owner'),
 ('20000000-0000-0000-0000-000000000182','10000000-0000-0000-0000-000000000181','00000000-0000-0000-0000-000000000182','Member','member');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select is(public.update_space_name('10000000-0000-0000-0000-000000000181','  Renamed  ','30000000-0000-0000-0000-000000000181')#>>'{data,space,name}','Renamed','owner can rename with trimmed input');
select is(public.increase_member_limit('10000000-0000-0000-0000-000000000181',5::smallint,'30000000-0000-0000-0000-000000000182')#>>'{data,space,member_limit}','5','owner can increase member limit');
select is(public.increase_member_limit('10000000-0000-0000-0000-000000000181',4::smallint,'30000000-0000-0000-0000-000000000183')#>>'{error,code}','MEMBER_LIMIT_NOT_INCREASED','member limit cannot be lowered');
select is((select invite_token_hash from public.spaces where id='10000000-0000-0000-0000-000000000181'),'mutable-space','settings changes preserve invite token');
select is(public.get_space_settings('10000000-0000-0000-0000-000000000181')#>>'{data,owner_actions,can_update_space_name}','true','owner settings expose rename capability');
select is(public.get_space_settings('10000000-0000-0000-0000-000000000181')#>>'{data,owner_actions,can_increase_member_limit}','true','owner can still increase below twelve');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select is(public.update_space_name('10000000-0000-0000-0000-000000000181','Denied','30000000-0000-0000-0000-000000000184')#>>'{error,code}','NOT_SPACE_OWNER','member cannot rename space');
select is(public.increase_member_limit('10000000-0000-0000-0000-000000000181',6::smallint,'30000000-0000-0000-0000-000000000185')#>>'{error,code}','NOT_SPACE_OWNER','member cannot raise limit');

reset role;
select is(lower(public.next_goal_period('Asia/Shanghai','weekly','2026-08-03 15:59Z')),'2026-08-03 16:00Z'::timestamptz,'weekly goal starts at next local midnight');
select is(upper(public.next_goal_period('Asia/Shanghai','weekly','2026-08-03 15:59Z')),'2026-08-10 16:00Z'::timestamptz,'weekly goal lasts seven local days');
select is(upper(public.next_goal_period('Asia/Shanghai','monthly','2026-08-03 15:59Z')),'2026-09-03 16:00Z'::timestamptz,'monthly goal rolls to same local day next month');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select is(public.propose_goal('10000000-0000-0000-0000-000000000181','group_total_minutes','weekly',300,'30000000-0000-0000-0000-000000000186')#>>'{data,proposal,status}','pending','first proposal is created');
select is(public.propose_goal('10000000-0000-0000-0000-000000000181','group_total_minutes','daily',30,'30000000-0000-0000-0000-000000000187')#>>'{error,code}','GOAL_ALREADY_OPEN','second pending proposal is blocked');
reset role;
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000183','10000000-0000-0000-0000-000000000181','00000000-0000-0000-0000-000000000183','Later','member');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select is(public.vote_goal_proposal((select id from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000181'),'accepted','30000000-0000-0000-0000-000000000188')#>>'{data,proposal,status}','accepted','last original voter accepts proposal');
reset role;
select is((select count(*)::int from public.goal_participants gp join public.goals g on g.id=gp.goal_id where g.space_id='10000000-0000-0000-0000-000000000181'),2,'member joining after proposal is excluded from accepted goal');
update public.goals set status='completed',completed_at=now() where space_id='10000000-0000-0000-0000-000000000181';
select is((select tier from public.achievements where space_id='10000000-0000-0000-0000-000000000181' and dedupe_key='goal-count:1'),'bronze','first completed goal earns bronze tier');
select ok((select participants_recorded from public.achievements where space_id='10000000-0000-0000-0000-000000000181' and dedupe_key='goal-count:1'),'goal achievement freezes participant provenance');
select is((select count(*)::int from public.achievement_participants ap join public.achievements a on a.id=ap.achievement_id where a.space_id='10000000-0000-0000-0000-000000000181' and a.dedupe_key='goal-count:1'),2,'goal achievement records the accepted participant snapshot');

select * from finish();
rollback;
