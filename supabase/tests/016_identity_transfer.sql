begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000161'),
 ('00000000-0000-0000-0000-000000000162'),
 ('00000000-0000-0000-0000-000000000163'),
 ('00000000-0000-0000-0000-000000000164');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000161','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000161','Transfer','00000000-0000-0000-0000-000000000161','UTC','transfer-room');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000161','10000000-0000-0000-0000-000000000161','00000000-0000-0000-0000-000000000161','Mover','owner');

select is((select count(*)::int from private.identity_bindings where auth_user_id in(
 '00000000-0000-0000-0000-000000000161','00000000-0000-0000-0000-000000000162','00000000-0000-0000-0000-000000000163','00000000-0000-0000-0000-000000000164')),4,'new auth users receive self bindings');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',true);
create temporary table first_code as select public.create_identity_transfer_code() result;
select matches((select result#>>'{data,transfer_code}' from first_code),'^[A-Za-z0-9_-]{32}$','source receives a 192-bit base64url transfer code');
select ok(not exists(select 1 from private.identity_transfer_codes where token_hash=(select result#>>'{data,transfer_code}' from first_code)),'private storage never contains the plaintext code');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
select is(public.redeem_identity_transfer_code((select result#>>'{data,transfer_code}' from first_code))#>>'{data,transferred}','true','fresh target redeems the code');
select is(private.current_principal_id(),'00000000-0000-0000-0000-000000000161'::uuid,'new auth session resolves to the original principal');
select is(public.get_my_membership()#>>'{data,membership,space_id}','10000000-0000-0000-0000-000000000161','new device sees the original membership');
select is(public.redeem_identity_transfer_code((select result#>>'{data,transfer_code}' from first_code))#>>'{error,code}','TRANSFER_CODE_USED','a consumed code cannot be replayed');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',true);
select is(private.current_principal_id(),null::uuid,'old auth session is revoked immediately');
select is(public.get_my_membership()#>>'{error,code}','AUTH_REQUIRED','old device loses RPC access immediately');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000162',true);
create temporary table second_code as select public.create_identity_transfer_code() result;
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000163','UTC');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000163',true);
select is(public.redeem_identity_transfer_code((select result#>>'{data,transfer_code}' from second_code))#>>'{error,code}','TARGET_IDENTITY_NOT_EMPTY','non-pristine target cannot replace its identity');
select is((select consumed_at from private.identity_transfer_codes where token_hash=private.identity_transfer_hash((select result#>>'{data,transfer_code}' from second_code))),null::timestamptz,'failed target validation does not consume the code');

update private.identity_transfer_codes set created_at=now()-interval '11 minutes',expires_at=now()-interval '1 second'
 where token_hash=private.identity_transfer_hash((select result#>>'{data,transfer_code}' from second_code));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000164',true);
select is(public.redeem_identity_transfer_code((select result#>>'{data,transfer_code}' from second_code))#>>'{error,code}','TRANSFER_CODE_EXPIRED','expired code is rejected');
select is((select failed_attempts from private.identity_transfer_codes where token_hash=private.identity_transfer_hash((select result#>>'{data,transfer_code}' from second_code))),1::smallint,'expired redemption is counted');
select is((select count(*)::int from private.identity_bindings where principal_user_id='00000000-0000-0000-0000-000000000161' and active),1,'principal always has exactly one active binding');

select * from finish();
rollback;
