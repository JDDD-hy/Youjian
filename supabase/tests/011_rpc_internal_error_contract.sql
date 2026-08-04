begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- Browser tests may intentionally exercise failed RPCs before pgTAP runs.
-- Isolate this contract test from those persistent audit rows.
delete from private.rpc_internal_errors;

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000131'),
 ('00000000-0000-0000-0000-000000000132');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000132','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values(
 '10000000-0000-0000-0000-000000000132','Collision holder','00000000-0000-0000-0000-000000000132','UTC',
 public.invite_hash(public.derive_invite_token('00000000-0000-0000-0000-000000000131','30000000-0000-0000-0000-000000000131','create_space'))
);
insert into public.space_members(id,space_id,user_id,display_name,role) values(
 '20000000-0000-0000-0000-000000000132','10000000-0000-0000-0000-000000000132','00000000-0000-0000-0000-000000000132','Holder','owner'
);

create temporary table rpc_results(label text primary key,result jsonb);
grant select,insert on rpc_results to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
insert into rpc_results values('constraint',public.create_space('Actor','New space','UTC','UTC',3::smallint,'30000000-0000-0000-0000-000000000131'));
insert into rpc_results values('business',public.create_space('Actor','New space','UTC','UTC',null::smallint,'30000000-0000-0000-0000-000000000132'));
reset role;

select is((select result#>>'{error,code}' from rpc_results where label='constraint'),'INTERNAL_ERROR','an unhandled unique constraint exception maps to INTERNAL_ERROR');
select ok((select result->>'request_id' from rpc_results where label='constraint') is not null,'internal error envelope includes a top-level request id');
select is((select result#>'{error,details}' from rpc_results where label='constraint'),'{}'::jsonb,'internal error details do not duplicate or hide the correlation id');
select ok(exists(
 select 1 from private.rpc_internal_errors e join rpc_results r on e.request_id=(r.result->>'request_id')::uuid
 where r.label='constraint' and e.actor_id='00000000-0000-0000-0000-000000000131' and e.rpc_name='create_space' and e.error_code='23505'
),'constraint audit stores only request identity, actor, RPC and SQLSTATE');
select ok(not exists(select 1 from public.profiles where id='00000000-0000-0000-0000-000000000131'),'failed implementation writes are rolled back before the private audit is recorded');
select is((select result#>>'{error,code}' from rpc_results where label='business'),'INVALID_MEMBER_LIMIT','explicit business errors remain unchanged');
select is((select count(*)::int from private.rpc_internal_errors),1,'business error envelopes do not create internal-error audit rows');
select is((
 select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname like 'rpc_impl_%'
 and not has_function_privilege('anon',p.oid,'execute') and not has_function_privilege('authenticated',p.oid,'execute')
),29,'all private RPC implementations are inaccessible to clients');

-- Test the same public wrapper against a representative permission failure.
-- Ownership is changed only inside this rolled-back test transaction.
grant usage,create on schema private to authenticated;
alter function private.rpc_impl_create_space(text,text,text,text,smallint,uuid) owner to authenticated;
revoke create,usage on schema private from authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000131',true);
insert into rpc_results values('permission',public.create_space('Actor','Permission space','UTC','UTC',3::smallint,'30000000-0000-0000-0000-000000000133'));
reset role;
select is((select result#>>'{error,code}' from rpc_results where label='permission'),'INTERNAL_ERROR','an unhandled permission exception maps to INTERNAL_ERROR');
select ok(exists(
 select 1 from private.rpc_internal_errors e join rpc_results r on e.request_id=(r.result->>'request_id')::uuid
 where r.label='permission' and e.rpc_name='create_space' and e.error_code='42501'
),'permission audit records the sanitized SQLSTATE without the PostgreSQL message');

set local role authenticated;
select throws_ok($$select * from private.rpc_internal_errors$$,'42501',null,'clients cannot read internal error audit');
select throws_ok($$select private.rpc_impl_create_space('A','B','UTC','UTC',3,gen_random_uuid())$$,'42501',null,'clients cannot bypass the public safe wrapper');
reset role;

select is((
 select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prorettype='jsonb'::regtype
 and(has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))
 and p.prosrc like '%rpc_internal_error_envelope%'
),29,'all 29 client-executable JSONB RPCs use the shared internal-error envelope');
select is((
 select array_agg(column_name::text order by ordinal_position) from information_schema.columns
 where table_schema='private' and table_name='rpc_internal_errors'
),array['request_id','actor_id','rpc_name','error_code','occurred_at'],'internal-error audit schema has no parameter, token, nickname, task, SQL text or message column');
select isnt((select result->>'request_id' from rpc_results where label='constraint'),(select result->>'request_id' from rpc_results where label='permission'),'each unexpected failure receives a distinct request id');
select is((select count(*)::int from private.rpc_internal_errors),2,'only the two unexpected failures are audited');
insert into private.rpc_internal_errors(request_id,rpc_name,error_code,occurred_at) values('80000000-0000-0000-0000-000000000131','retention_probe','XX000',now()-interval '91 days');
select public.run_minute_maintenance();
select ok(not exists(select 1 from private.rpc_internal_errors where request_id='80000000-0000-0000-0000-000000000131'),'internal-error audit older than 90 days is removed by maintenance');

select * from finish();
rollback;
