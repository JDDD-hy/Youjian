begin;
create extension if not exists pgtap with schema extensions;
select plan(21);
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000011'),('00000000-0000-0000-0000-000000000012'),
 ('00000000-0000-0000-0000-000000000013'),('00000000-0000-0000-0000-000000000014');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
set local role authenticated;
create temporary table create_response as select public.create_space('Alice','Study Room','Asia/Shanghai','Asia/Shanghai',2::smallint,'30000000-0000-0000-0000-000000000001'::uuid) response;
select is((select response->>'ok' from create_response),'true','owner creates a space');
create temporary table test_state as
select id space_id, regexp_replace((select response#>>'{data,invite,invite_url}' from create_response),'^.*/','') token,
 invite_token_hash old_hash from public.spaces;
select is((select count(*)::int from public.spaces where owner_id='00000000-0000-0000-0000-000000000011'),1,'create inserts one space');
select is((select count(*)::int from public.space_members where space_id=(select space_id from test_state)),1,'create inserts owner membership');
select isnt((select token from test_state),(select old_hash from test_state),'plaintext invite is not stored as hash');
select is(public.create_space('Alice','Study Room','Asia/Shanghai','Asia/Shanghai',2::smallint,'30000000-0000-0000-0000-000000000001'::uuid),(select response from create_response),'secret response is deterministically replayable');
reset role;
select ok(not exists(select 1 from public.focus_commands where result::text like '%/invite/%'),'idempotency storage contains no plaintext invite URL');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select is(public.get_invite_preview((select token from test_state))#>>'{data,status}','valid','public invite preview is valid');
select ok(not ((public.get_invite_preview((select token from test_state))#>'{data}') ? 'space_id'),'preview never exposes space id');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',true);
create temporary table join_response as select public.join_space((select token from test_state),'Bob','Europe/Paris','30000000-0000-0000-0000-000000000002') response;
select is((select response->>'ok' from join_response),'true','second identity joins');
select is(public.join_space((select token from test_state),'Bob','Europe/Paris','30000000-0000-0000-0000-000000000002'),(select response from join_response),
 'same idempotency key returns exact original result');
select is(public.get_invite_preview((select token from test_state))#>>'{data,status}','full','preview reports full room');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000013',true);
select is(public.join_space((select token from test_state),'Carol','UTC','30000000-0000-0000-0000-000000000003')#>>'{error,code}','SPACE_FULL','room capacity enforced');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
create temporary table rotate_response as select public.rotate_invite((select space_id from test_state),'30000000-0000-0000-0000-000000000004') response;
select is((select response->>'ok' from rotate_response),'true','owner rotates invite');
select is(public.get_invite_preview((select token from test_state))#>>'{error,code}','INVITE_INVALID','old token immediately expires');
select is((select invite_version from public.spaces where id=(select space_id from test_state)),2,'rotation increments invite version');
select is(public.rotate_invite((select space_id from test_state),'30000000-0000-0000-0000-000000000004'),(select response from rotate_response),'rotation retry reproduces the same secret response');
reset role; select ok(not exists(select 1 from public.focus_commands where result::text like '%/invite/%'),'rotated invite plaintext is not persisted');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000012',true);
select is(public.rotate_invite((select space_id from test_state),'30000000-0000-0000-0000-000000000005')#>>'{error,code}','NOT_SPACE_OWNER','ordinary member cannot rotate invite');
select is(public.create_space('Bob','Another','UTC','UTC',3::smallint,'30000000-0000-0000-0000-000000000006'::uuid)#>>'{error,code}','ALREADY_IN_ANOTHER_SPACE','one identity cannot create second active space');
select is(public.join_space('invalid','X','UTC','30000000-0000-0000-0000-000000000002')#>>'{error,code}','IDEMPOTENCY_KEY_REUSED','same successful key with different parameters is rejected');
reset role;
select throws_ok($$insert into public.space_members(space_id,user_id,display_name,role) select space_id,'00000000-0000-0000-0000-000000000014','BOB','member' from test_state$$,
 '23505',null,'case-insensitive nickname constraint is race-safe');

select * from finish();
rollback;
