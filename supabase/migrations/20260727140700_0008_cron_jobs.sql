create function public.disable_member(p_space_id uuid,p_member_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a uuid:=auth.uid(); h text:=p_space_id::text||'|'||p_member_id::text; cached jsonb; m public.space_members%rowtype; sid uuid; result jsonb;
begin
 cached:=public.command_cached(a,p_idempotency_key,'disable_member',h); if cached is not null then return cached; end if;
 if not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
 select * into m from public.space_members where id=p_member_id and space_id=p_space_id for update;
 if not found then return public.api_error('MEMBER_NOT_FOUND'); end if;
 if m.role='owner' then return public.api_error('CANNOT_DISABLE_OWNER'); end if;
 if m.status='disabled' then return public.api_error('MEMBER_ALREADY_DISABLED'); end if;
 select id into sid from public.focus_sessions where member_id=m.id and status in ('focusing','paused') for update;
 if sid is not null then perform public.finish_focus_session(sid,now(),'member_disabled'); end if;
 update public.space_members set status='disabled',disabled_at=now(),disabled_by=a where id=m.id;
 delete from public.goal_proposal_members gpm using public.goal_proposals gp
 where gpm.proposal_id=gp.id and gpm.member_id=m.id and gp.status='pending';
 result:=public.api_ok(jsonb_build_object('member',jsonb_build_object('member_id',m.id,'status','disabled','disabled_at',now()),
   'settled_session',case when sid is null then null else public.session_json(sid) end,'resolved_proposals','[]'::jsonb));
 return public.store_command(a,p_idempotency_key,'disable_member',h,sid,result);
end $$;

create function public.run_minute_maintenance() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; settled int:=0; uncertain int:=0; t timestamptz:=now();
begin
 for r in select id from public.focus_sessions where status='paused' and paused_at+interval '15 minutes'<=t
   or status='focusing' and active_segment_started_at+make_interval(secs=>21600-accumulated_focus_seconds)<=t for update skip locked
 loop perform public.settle_session(r.id,t); settled:=settled+1; end loop;
 for r in select id,last_seen_at from public.focus_sessions where status='focusing' and last_seen_at+interval '120 seconds'<=t for update skip locked
 loop
   if not exists(select 1 from public.focus_connection_intervals where session_id=r.id and ended_at is null) then
     insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(r.id,r.last_seen_at+interval '120 seconds',r.last_seen_at);
     perform public.record_focus_event(r.id,null,'connection_unconfirmed',r.last_seen_at+interval '120 seconds'); uncertain:=uncertain+1;
   end if;
 end loop;
 delete from public.focus_commands where created_at<t-interval '30 days';
 return jsonb_build_object('settled_sessions',settled,'new_unconfirmed_intervals',uncertain,'ran_at',t);
end $$;
revoke all on function public.run_minute_maintenance(), public.disable_member(uuid,uuid,uuid) from public;
grant execute on function public.disable_member(uuid,uuid,uuid) to authenticated;

do $$ begin
  if not exists(select 1 from cron.job where jobname='youjian-minute-maintenance') then
    perform cron.schedule('youjian-minute-maintenance','* * * * *','select public.run_minute_maintenance()');
  end if;
end $$;

alter publication supabase_realtime add table public.focus_sessions;
alter publication supabase_realtime add table public.space_members;
