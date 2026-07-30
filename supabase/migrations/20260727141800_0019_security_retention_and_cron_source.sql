create table private.invite_preview_rate_buckets(
 bucket_kind text not null check(bucket_kind in('ip','token')),
 bucket_hash text not null,
 window_start timestamptz not null,
 request_count integer not null check(request_count>0),
 primary key(bucket_kind,bucket_hash,window_start)
);
create table private.client_error_rate_limits(
 actor_id uuid not null references auth.users(id) on delete cascade,
 window_start timestamptz not null,
 request_count integer not null check(request_count>0),
 primary key(actor_id,window_start)
);
revoke all on private.invite_preview_rate_buckets,private.client_error_rate_limits from public,anon,authenticated;

-- Kong appends the socket source to X-Forwarded-For. Use only its rightmost
-- address, so a client-supplied prefix cannot select the database rate bucket.
create function private.request_client_ip_hash() returns text
language plpgsql stable security definer set search_path='' as $$
declare headers jsonb; forwarded text; candidate text; address inet;
begin
 headers:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb);
 forwarded:=nullif(headers->>'x-forwarded-for','');
 if forwarded is not null then candidate:=btrim((string_to_array(forwarded,','))[cardinality(string_to_array(forwarded,','))]); end if;
 begin address:=candidate::inet; exception when invalid_text_representation then address:=null; end;
 address:=coalesce(address,inet_client_addr(),'0.0.0.0'::inet);
 return encode(extensions.digest(convert_to(host(address),'UTF8'),'sha256'),'hex');
end $$;
revoke all on function private.request_client_ip_hash() from public,anon,authenticated;

create or replace function public.get_invite_preview(p_invite_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.spaces%rowtype; owner_name text; n int; th text; ih text; ws timestamptz; ip_hits int; token_hits int; retry_seconds int;
begin
 th:=public.invite_hash(coalesce(p_invite_token,'')); ih:=private.request_client_ip_hash();
 ws:=to_timestamp(floor(extract(epoch from now())/300)*300);
 insert into private.invite_preview_rate_buckets(bucket_kind,bucket_hash,window_start,request_count) values('ip',ih,ws,1)
 on conflict(bucket_kind,bucket_hash,window_start) do update set request_count=private.invite_preview_rate_buckets.request_count+1 returning request_count into ip_hits;
 insert into private.invite_preview_rate_buckets(bucket_kind,bucket_hash,window_start,request_count) values('token',th,ws,1)
 on conflict(bucket_kind,bucket_hash,window_start) do update set request_count=private.invite_preview_rate_buckets.request_count+1 returning request_count into token_hits;
 if ip_hits>30 or token_hits>30 then
  retry_seconds:=greatest(0,ceil(extract(epoch from(ws+interval '5 minutes'-now())))::int);
  return public.api_error('RATE_LIMITED',jsonb_build_object('retry_after_seconds',retry_seconds));
 end if;
 if p_invite_token is null or length(p_invite_token)<40 then return public.api_error('INVITE_INVALID'); end if;
 select * into s from public.spaces where invite_token_hash=th; if not found then return public.api_error('INVITE_INVALID'); end if;
 select count(*),max(display_name) filter(where role='owner') into n,owner_name from public.space_members where space_id=s.id and status='active';
 return public.api_ok(jsonb_build_object('status',case when n>=s.member_limit then 'full' else 'valid' end,'space_name',s.name,'owner_display_name',owner_name,
  'active_member_count',n,'member_limit',s.member_limit,'space_timezone',s.timezone));
end $$;

create or replace function public.report_client_error(p_error_code text,p_route text default null,p_metadata jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); rid uuid; ws timestamptz; hits int; retry_seconds int;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_error_code is null or p_error_code!~'^[A-Z0-9_.-]{1,80}$' or p_route is not null and(char_length(p_route)>200 or p_route~*'(/invite/[^/?#]+|[?&](token|authorization|email)=)') or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then return public.api_error('INVALID_ERROR_REPORT'); end if;
 if private.json_contains_sensitive_key(p_metadata) then return public.api_error('SENSITIVE_METADATA_REJECTED'); end if;
 if octet_length(p_metadata::text)>4096 then return public.api_error('INVALID_ERROR_REPORT'); end if;
 ws:=to_timestamp(floor(extract(epoch from now())/600)*600);
 insert into private.client_error_rate_limits(actor_id,window_start,request_count) values(a,ws,1)
 on conflict(actor_id,window_start) do update set request_count=private.client_error_rate_limits.request_count+1 returning request_count into hits;
 if hits>20 then
  retry_seconds:=greatest(0,ceil(extract(epoch from(ws+interval '10 minutes'-now())))::int);
  return public.api_error('RATE_LIMITED',jsonb_build_object('retry_after_seconds',retry_seconds));
 end if;
 insert into private.client_error_reports(actor_id,error_code,route,metadata) values(a,p_error_code,p_route,p_metadata) returning id into rid;
 return public.api_ok(jsonb_build_object('report_id',rid));
end $$;

alter table private.maintenance_runs add column source text not null default 'lazy' check(source in('cron','lazy','manual'));

create function private.run_minute_maintenance_as(p_source text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare run_id bigint; output jsonb; t timestamptz:=now(); started_clock timestamptz:=clock_timestamp(); duration int;
begin
 if p_source not in('cron','lazy','manual') then raise exception 'invalid maintenance source' using errcode='22023'; end if;
 insert into private.maintenance_runs(job_name,started_at,status,source) values('minute_maintenance',t,'running',p_source) returning id into run_id;
 begin
  delete from private.invite_preview_rate_limits where window_start<t-interval '1 day';
  delete from private.invite_preview_rate_buckets where window_start<t-interval '1 day';
  delete from private.client_error_rate_limits where window_start<t-interval '1 day';
  delete from private.client_error_reports where occurred_at<t-interval '90 days';
  delete from private.maintenance_runs where started_at<t-interval '30 days' and id<>run_id;
  output:=public.run_minute_maintenance_core(t); duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='succeeded',result=output where id=run_id; return output;
 exception when others then
  duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='failed',error_code=sqlstate,result=jsonb_build_object('message','maintenance failed') where id=run_id;
  return jsonb_build_object('ok',false,'error_code','MAINTENANCE_FAILED','run_id',run_id,'ran_at',t);
 end;
end $$;

create or replace function public.run_minute_maintenance() returns jsonb
language sql security definer set search_path='' as $$select private.run_minute_maintenance_as('lazy')$$;
create function private.run_scheduled_minute_maintenance() returns jsonb
language sql security definer set search_path='' as $$select private.run_minute_maintenance_as('cron')$$;
create function private.run_manual_minute_maintenance() returns jsonb
language sql security definer set search_path='' as $$select private.run_minute_maintenance_as('manual')$$;

revoke all on function private.run_minute_maintenance_as(text),private.run_scheduled_minute_maintenance(),private.run_manual_minute_maintenance() from public,anon,authenticated;
revoke all on function public.get_invite_preview(text),public.report_client_error(text,text,jsonb),public.run_minute_maintenance() from public;
grant execute on function public.get_invite_preview(text) to anon,authenticated;
grant execute on function public.report_client_error(text,text,jsonb) to authenticated;

do $$begin
 if exists(select 1 from cron.job where jobname='youjian-minute-maintenance') then perform cron.unschedule('youjian-minute-maintenance'); end if;
 perform cron.schedule('youjian-minute-maintenance','* * * * *','select private.run_scheduled_minute_maintenance()');
end$$;
