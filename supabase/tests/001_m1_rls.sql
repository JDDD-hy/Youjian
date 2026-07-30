begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000001','Asia/Shanghai'),('00000000-0000-0000-0000-000000000002','Europe/Paris'),('00000000-0000-0000-0000-000000000003','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000001','Alpha','00000000-0000-0000-0000-000000000001','Asia/Shanghai','hash-a'),
 ('10000000-0000-0000-0000-000000000002','Beta','00000000-0000-0000-0000-000000000003','UTC','hash-b');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Owner','owner'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','Friend','member'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','Other','owner');

select ok(public.validate_iana_timezone('Asia/Shanghai'),'valid IANA timezone');
select ok(not public.validate_iana_timezone('Mars/Olympus'),'invalid IANA timezone');
select is(public.normalize_display_name('  Alice  '),'alice','display names normalize case and whitespace');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select is((select count(*)::int from public.spaces),1,'member sees own space only');
select is((select count(*)::int from public.space_members),2,'member sees members in own space only');
select ok(public.current_user_is_active_member('10000000-0000-0000-0000-000000000001'),'active member helper');
select ok(not public.current_user_is_owner('10000000-0000-0000-0000-000000000001'),'ordinary member is not owner');
select throws_ok($$insert into public.spaces(name,owner_id,timezone,invite_token_hash) values('Nope','00000000-0000-0000-0000-000000000002','UTC','x')$$,
 '42501',null,'authenticated client cannot directly create spaces');
select throws_ok($$update public.space_members set display_name='Hacked' where id='20000000-0000-0000-0000-000000000001'$$,
 '42501',null,'ordinary member cannot directly manage members');
select throws_ok($$insert into public.focus_sessions(space_id,user_id,member_id,task_name,status,active_segment_started_at)
 values('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Bypass','focusing',now())$$,
 '42501',null,'client cannot directly write core focus table');

reset role;
update public.space_members set status='disabled',disabled_at=now(),disabled_by='00000000-0000-0000-0000-000000000001'
 where id='20000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select is((select count(*)::int from public.spaces),0,'disabled member immediately loses space read access');
select is((select count(*)::int from public.space_members),0,'disabled member immediately loses member reads');

reset role;
select throws_ok($$update public.space_members set status='disabled',disabled_at=now(),disabled_by='00000000-0000-0000-0000-000000000001'
 where id='20000000-0000-0000-0000-000000000001'$$,'23514',null,'owner cannot be disabled');
select throws_ok($$insert into public.space_members(space_id,user_id,display_name,role) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003',' OWNER ','member')$$,
 '23514',null,'non-trimmed display names are rejected');
select throws_ok($$insert into public.space_members(space_id,user_id,display_name,role) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','owner','member')$$,
 '23505',null,'active display name uniqueness is case-insensitive');

select * from finish();
rollback;
