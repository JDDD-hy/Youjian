begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

insert into auth.users(id) values('00000000-0000-0000-0000-000000000121');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000121','UTC');

create temporary table observed_ip_hash(value text);
select set_config('request.headers','{"x-forwarded-for":"198.51.100.77, 203.0.113.10"}',true);
insert into observed_ip_hash values(private.request_client_ip_hash());
select set_config('request.headers','{"x-forwarded-for":"192.0.2.88, 203.0.113.10"}',true);
select is(private.request_client_ip_hash(),(select value from observed_ip_hash),'a forged X-Forwarded-For prefix cannot select a new IP bucket');
select ok(not has_function_privilege('anon','private.request_client_ip_hash()','execute'),'clients cannot invoke the trusted IP helper');

delete from private.invite_preview_rate_buckets;
do $$declare i int; begin
 for i in 1..30 loop
  perform set_config('request.headers','{"x-forwarded-for":"198.51.100.'||i||', 203.0.113.20"}',true);
  perform public.get_invite_preview('rotating-token-'||lpad(i::text,3,'0')||repeat('x',40));
 end loop;
end$$;
select set_config('request.headers','{"x-forwarded-for":"192.0.2.250, 203.0.113.20"}',true);
select is(public.get_invite_preview('rotating-token-031'||repeat('x',40))#>>'{error,code}','RATE_LIMITED','rotating invite tokens and forged prefixes cannot bypass the independent IP limit');
select is((select count(*)::int from private.invite_preview_rate_buckets where bucket_kind='ip'),1,'one source IP creates one IP bucket rather than token-IP combination buckets');
select is((select count(*)::int from private.invite_preview_rate_buckets where bucket_kind='token'),31,'token buckets are stored independently of the IP bucket');

delete from private.invite_preview_rate_buckets;
do $$declare i int; begin
 for i in 1..30 loop
  perform set_config('request.headers',jsonb_build_object('x-forwarded-for','203.0.113.'||i)::text,true);
  perform public.get_invite_preview('shared-token-'||repeat('y',40));
 end loop;
end$$;
select set_config('request.headers','{"x-forwarded-for":"203.0.113.200"}',true);
select is(public.get_invite_preview('shared-token-'||repeat('y',40))#>>'{error,code}','RATE_LIMITED','changing source IP cannot bypass the independent token limit');
select is((select count(*)::int from private.invite_preview_rate_buckets where bucket_kind='token'),1,'all source IPs share one token bucket');
select is((select count(*)::int from private.invite_preview_rate_buckets where bucket_kind='ip'),31,'independent buckets avoid an IP-token cross-product table');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000121',true);
do $$begin for i in 1..20 loop perform public.report_client_error('UI_RATE','/home',jsonb_build_object('component','Home')); end loop; end$$;
select is(public.report_client_error('UI_RATE','/home',jsonb_build_object('component','Home'))#>>'{error,code}','RATE_LIMITED','client error reports are limited independently per authenticated user');
reset role;
select is((select count(*)::int from private.client_error_reports where actor_id='00000000-0000-0000-0000-000000000121' and error_code='UI_RATE'),20,'rate-limited client errors are not persisted');
set local role authenticated;
select throws_ok($$select * from private.client_error_rate_limits$$,'42501',null,'clients cannot read client-error rate buckets');
reset role;

insert into private.client_error_reports(id,actor_id,occurred_at,error_code,route,metadata) values
 ('70000000-0000-0000-0000-000000000121','00000000-0000-0000-0000-000000000121',now()-interval '91 days','OLD_REPORT','/home','{}'),
 ('70000000-0000-0000-0000-000000000122','00000000-0000-0000-0000-000000000121',now()-interval '89 days','RECENT_REPORT','/home','{}');
insert into private.maintenance_runs(job_name,started_at,finished_at,status,result,source) values
 ('minute_maintenance',now()-interval '31 days',now()-interval '31 days','succeeded','{}','cron'),
 ('minute_maintenance',now()-interval '29 days',now()-interval '29 days','succeeded','{}','cron');
select lives_ok($$select public.run_minute_maintenance()$$,'public lazy maintenance runs retention cleanup');
select ok(not exists(select 1 from private.client_error_reports where id='70000000-0000-0000-0000-000000000121'),'client error reports older than 90 days are removed');
select ok(exists(select 1 from private.client_error_reports where id='70000000-0000-0000-0000-000000000122'),'client error reports inside 90 days are retained');
select ok(not exists(select 1 from private.maintenance_runs where started_at<now()-interval '30 days'),'maintenance runs older than 30 days are removed');
select is((select source from private.maintenance_runs order by id desc limit 1),'lazy','the public maintenance entry point can only record lazy source');

select lives_ok($$select private.run_scheduled_minute_maintenance()$$,'private scheduled maintenance wrapper runs');
select is((select source from private.maintenance_runs order by id desc limit 1),'cron','scheduled wrapper records cron source');
select lives_ok($$select private.run_manual_minute_maintenance()$$,'private manual maintenance wrapper runs');
select is((select source from private.maintenance_runs order by id desc limit 1),'manual','manual wrapper records manual source');
select ok(not has_function_privilege('authenticated','private.run_scheduled_minute_maintenance()','execute'),'authenticated clients cannot impersonate cron');
select is((select command from cron.job where jobname='youjian-minute-maintenance'),'select private.run_scheduled_minute_maintenance()','pg_cron invokes the source-tagging private wrapper');

select * from finish();
rollback;
