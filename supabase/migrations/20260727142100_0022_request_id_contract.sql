create or replace function private.rpc_internal_error_envelope(p_rpc_name text,p_error_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rid uuid:=gen_random_uuid(); safe_code text;
begin
 safe_code:=case when coalesce(p_error_code,'')~'^[0-9A-Z]{5}$' then p_error_code else 'XX000' end;
 insert into private.rpc_internal_errors(request_id,actor_id,rpc_name,error_code) values(rid,auth.uid(),p_rpc_name,safe_code);
 return public.api_error('INTERNAL_ERROR','{}'::jsonb,null,rid);
end $$;
revoke all on function private.rpc_internal_error_envelope(text,text) from public,anon,authenticated;
