begin;
create extension if not exists pgtap with schema extensions;
select plan(15);
select ok(has_function_privilege('anon','public.get_invite_preview(text)','execute'),'anon may execute invite preview');
select ok(not has_function_privilege('anon','public.start_focus(uuid,text,text,uuid)','execute'),'anon cannot execute focus writes');
select ok(has_function_privilege('authenticated','public.start_focus(uuid,text,text,uuid)','execute'),'authenticated may execute focus writes');
select ok(not has_function_privilege('authenticated','public.run_minute_maintenance()','execute'),'maintenance is not client executable');
select ok(not has_function_privilege('authenticated','public.derive_invite_token(uuid,uuid,text)','execute'),'token derivation is private');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x where n.nspname='public' and x.grantee=0 and x.privilege_type='EXECUTE'),0,'no public-schema function retains PUBLIC execute');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),0,'every public application table has RLS');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and not coalesce(p.proconfig,'{}')@>array['search_path=""']),0,'every security-definer function fixes empty search_path');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.prosecdef and not coalesce(p.proconfig,'{}')@>array['search_path=""']),0,'every private security-definer function fixes empty search_path');
select ok(not has_schema_privilege('anon','private','usage') and not has_schema_privilege('authenticated','private','usage'),'private secret schema is inaccessible');
insert into auth.users(id) values('00000000-0000-0000-0000-000000000081'),('00000000-0000-0000-0000-000000000082');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000081','UTC'),('00000000-0000-0000-0000-000000000082','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values('10000000-0000-0000-0000-000000000081','ACL','00000000-0000-0000-0000-000000000081','UTC','acl');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000081','A','owner'),
 ('20000000-0000-0000-0000-000000000082','10000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000082','B','member');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,active_segment_started_at) values
 ('40000000-0000-0000-0000-000000000081','10000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000081','20000000-0000-0000-0000-000000000081','Owned by A','focusing',now());
insert into public.focus_segments(session_id,started_at) values('40000000-0000-0000-0000-000000000081',now());
set local role anon;
select throws_ok($$select public.start_focus(gen_random_uuid(),'x','work',gen_random_uuid())$$,'42501',null,'anon focus call is denied by ACL');
reset role;
set local role authenticated; select set_config('request.jwt.claim.sub','',true);
select is(public.pause_focus('40000000-0000-0000-0000-000000000999','30000000-0000-0000-0000-000000000099')#>>'{error,code}','AUTH_REQUIRED','missing auth identity is rejected before lookup');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000082',true);
select is(public.pause_focus('40000000-0000-0000-0000-000000000081','30000000-0000-0000-0000-000000000098')#>>'{error,code}','SESSION_NOT_FOUND','another member session is not enumerable');
select throws_ok($$select * from public.focus_commands$$,'42501',null,'authenticated client cannot inspect idempotency records');
select throws_ok($$insert into public.achievement_reads(achievement_id,member_id) values(gen_random_uuid(),gen_random_uuid())$$,'42501',null,'authenticated client cannot forge achievement reads');
select * from finish(); rollback;
