create or replace function public.get_invite_preview(p_invite_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.spaces%rowtype; owner_name text; n int; headers jsonb; client_ip text; th text; ch text; ws timestamptz; hits int;
begin
 headers:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb);
 client_ip:=coalesce(nullif(headers->>'cf-connecting-ip',''),nullif(split_part(coalesce(headers->>'x-forwarded-for',''),',',1),''),nullif(headers->>'x-real-ip',''),'unknown');
 th:=public.invite_hash(coalesce(p_invite_token,'')); ch:=encode(extensions.digest(convert_to(client_ip,'UTF8'),'sha256'),'hex');
 ws:=to_timestamp(floor(extract(epoch from now())/300)*300);
 insert into private.invite_preview_rate_limits(token_hash,client_hash,window_start,request_count) values(th,ch,ws,1)
 on conflict(token_hash,client_hash,window_start) do update set request_count=private.invite_preview_rate_limits.request_count+1 returning request_count into hits;
 if hits>30 then return public.api_error('RATE_LIMITED',jsonb_build_object('retry_after_seconds',greatest(0,ceil(extract(epoch from(ws+interval '5 minutes'-now())))::int))); end if;
 if p_invite_token is null or length(p_invite_token)<40 then return public.api_error('INVITE_INVALID'); end if;
 select * into s from public.spaces where invite_token_hash=th; if not found then return public.api_error('INVITE_INVALID'); end if;
 select count(*),max(display_name) filter(where role='owner') into n,owner_name from public.space_members where space_id=s.id and status='active';
 return public.api_ok(jsonb_build_object('status',case when n>=s.member_limit then 'full' else 'valid' end,'space_name',s.name,'owner_display_name',owner_name,
  'active_member_count',n,'member_limit',s.member_limit,'space_timezone',s.timezone));
exception when invalid_text_representation then return public.api_error('INVITE_INVALID');
end $$;

create or replace function public.run_minute_maintenance() returns jsonb
language plpgsql security definer set search_path='' as $$
declare run_id bigint; output jsonb; t timestamptz:=now(); started_clock timestamptz:=clock_timestamp(); duration int;
begin
 insert into private.maintenance_runs(job_name,started_at,status) values('minute_maintenance',t,'running') returning id into run_id;
 begin
  delete from private.invite_preview_rate_limits where window_start<t-interval '1 day';
  output:=public.run_minute_maintenance_core(t); duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='succeeded',result=output where id=run_id; return output;
 exception when others then
  duration:=greatest(0,floor(extract(epoch from(clock_timestamp()-started_clock))*1000)::int);
  update private.maintenance_runs set finished_at=clock_timestamp(),duration_ms=duration,status='failed',error_code=sqlstate,result=jsonb_build_object('message','maintenance failed') where id=run_id;
  return jsonb_build_object('ok',false,'error_code','MAINTENANCE_FAILED','run_id',run_id,'ran_at',t);
 end;
end $$;

revoke all on function public.get_invite_preview(text),public.run_minute_maintenance() from public;
grant execute on function public.get_invite_preview(text) to anon,authenticated;
