begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000151'),
 ('00000000-0000-0000-0000-000000000152'),
 ('00000000-0000-0000-0000-000000000153'),
 ('00000000-0000-0000-0000-000000000154');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000151','UTC'),
 ('00000000-0000-0000-0000-000000000152','UTC'),
 ('00000000-0000-0000-0000-000000000153','UTC'),
 ('00000000-0000-0000-0000-000000000154','UTC');
insert into public.spaces(id,name,owner_id,timezone,member_limit,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000151','Lifecycle','00000000-0000-0000-0000-000000000151','UTC',4,public.invite_hash(repeat('L',43)));
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000151','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000151','Owner','owner'),
 ('20000000-0000-0000-0000-000000000152','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000152','Leaving','member'),
 ('20000000-0000-0000-0000-000000000153','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000153','Successor','member');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select is(public.propose_goal('10000000-0000-0000-0000-000000000151','group_total_minutes','weekly',30,'30000000-0000-0000-0000-000000000151')#>>'{data,proposal,status}','pending','owner creates pending proposal before a member leaves');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000152',true);
select is(public.start_focus('10000000-0000-0000-0000-000000000151','Leaving focus','work','30000000-0000-0000-0000-000000000152')#>>'{data,session,status}','focusing','departing member can start focus');
update public.focus_sessions set active_segment_started_at=now()-interval '6 minutes' where task_name='Leaving focus';
update public.focus_segments set started_at=now()-interval '6 minutes' where ended_at is null;
create temporary table leave_result as select public.leave_space('10000000-0000-0000-0000-000000000151','30000000-0000-0000-0000-000000000153') result;
select is((select result#>>'{data,status}' from leave_result),'left','member can voluntarily leave');
select is((select completion_reason::text from public.focus_sessions where task_name='Leaving focus'),'member_left','leave settles active focus authoritatively');
select is((select accumulated_focus_seconds from public.focus_sessions where task_name='Leaving focus'),360,'leave preserves focused duration');
select is((select end_reason from public.space_members where id='20000000-0000-0000-0000-000000000152'),'left','membership records voluntary end reason');
select is((select status::text from public.goal_proposals where space_id='10000000-0000-0000-0000-000000000151'),'rejected','leave cancels a pending unanimous proposal');
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000151')#>>'{error,code}','SPACE_ACCESS_DENIED','departed member immediately loses access');
select is(public.leave_space('10000000-0000-0000-0000-000000000151','30000000-0000-0000-0000-000000000153'),(select result from leave_result),'leave retry is idempotent');
select is(public.get_my_membership()#>>'{data,latest_disabled_membership,end_reason}','left','membership reports a voluntary departure separately');
create temporary table rejoin_result as select public.join_space(repeat('L',43),'Returned','UTC','30000000-0000-0000-0000-000000000159') result;
select is((select result#>>'{data,membership,status}' from rejoin_result),'active','a voluntary leaver can rejoin with a valid invite');
select is((select result#>>'{data,membership,member_id}' from rejoin_result),'20000000-0000-0000-0000-000000000152','rejoin reuses the historical member identity');
select is((select display_name from public.space_members where id='20000000-0000-0000-0000-000000000152'),'Returned','rejoin can choose a current display name');
select is((select end_reason from public.space_members where id='20000000-0000-0000-0000-000000000152'),null,'rejoin clears the voluntary end marker');
insert into public.space_members(id,space_id,user_id,display_name,role,status,disabled_at,disabled_by,end_reason) values
 ('20000000-0000-0000-0000-000000000154','10000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000154','Removed','member','disabled',now(),'00000000-0000-0000-0000-000000000151','disabled');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000154',true);
select is(public.join_space(repeat('L',43),'Removed','UTC','30000000-0000-0000-0000-000000000160')#>>'{error,code}','MEMBER_DISABLED','a member removed by the owner still cannot rejoin');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);
select is(public.leave_space('10000000-0000-0000-0000-000000000151','30000000-0000-0000-0000-000000000154')#>>'{error,code}','OWNER_MUST_TRANSFER_OR_DISSOLVE','owner cannot leave without succession');
select is(public.transfer_ownership('10000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000153','30000000-0000-0000-0000-000000000155')#>>'{data,owner_member_id}','20000000-0000-0000-0000-000000000153','owner transfers to an active member');
select is((select owner_id from public.spaces where id='10000000-0000-0000-0000-000000000151'),'00000000-0000-0000-0000-000000000153'::uuid,'space owner id changes atomically');
select is((select count(*)::int from public.space_members where space_id='10000000-0000-0000-0000-000000000151' and role='owner' and status='active'),1,'transfer leaves exactly one active owner');
select is(public.transfer_ownership('10000000-0000-0000-0000-000000000151','20000000-0000-0000-0000-000000000153','30000000-0000-0000-0000-000000000156')#>>'{error,code}','NOT_SPACE_OWNER','former owner cannot transfer again');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',true);
select is(public.start_focus('10000000-0000-0000-0000-000000000151','Dissolve focus','reading','30000000-0000-0000-0000-000000000157')#>>'{data,session,status}','focusing','new owner can focus before dissolution');
update public.focus_sessions set active_segment_started_at=now()-interval '7 minutes' where task_name='Dissolve focus';
update public.focus_segments set started_at=now()-interval '7 minutes' where ended_at is null;
create temporary table dissolve_result as select public.dissolve_space('10000000-0000-0000-0000-000000000151','30000000-0000-0000-0000-000000000158') result;
select is((select result#>>'{data,status}' from dissolve_result),'dissolved','owner dissolves the room');
select is((select lifecycle_status from public.spaces where id='10000000-0000-0000-0000-000000000151'),'dissolved','space records dissolved lifecycle');
select is((select completion_reason::text from public.focus_sessions where task_name='Dissolve focus'),'space_dissolved','dissolution settles active focus');
select is((select count(*)::int from public.space_members where space_id='10000000-0000-0000-0000-000000000151' and status='active'),0,'dissolution removes all active access');
select is(public.get_invite_preview(repeat('L',43))#>>'{error,code}','INVITE_INVALID','dissolution invalidates the invite');
select is(public.dissolve_space('10000000-0000-0000-0000-000000000151','30000000-0000-0000-0000-000000000158'),(select result from dissolve_result),'dissolve retry is idempotent');

select * from finish();
rollback;
