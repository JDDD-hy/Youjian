alter table public.space_members add column version bigint not null default 1 check(version>0);
alter table public.goal_proposals add column version bigint not null default 1 check(version>0);
alter table public.goals add column version bigint not null default 1 check(version>0);
alter table public.achievements add column version bigint not null default 1 check(version>0);
create index focus_segments_time_range on public.focus_segments(started_at,ended_at) where ended_at is not null;

create function public.bump_entity_version() returns trigger language plpgsql set search_path='' as $$
begin if new.version=old.version then new.version:=old.version+1; end if; return new; end $$;
create trigger bump_member_version before update on public.space_members for each row execute function public.bump_entity_version();
create trigger bump_proposal_version before update on public.goal_proposals for each row execute function public.bump_entity_version();
create trigger bump_goal_version before update on public.goals for each row execute function public.bump_entity_version();

create or replace function public.finish_focus_session(p_session_id uuid,p_at timestamptz,p_reason public.completion_reason) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; v_end timestamptz; v_total int; v_status public.focus_status; v_uncertain int:=0; v_closed_seconds numeric:=0;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in ('completed','discarded') then return p_session_id; end if;
 v_end:=case when s.status='paused' then s.paused_at else p_at end;
 select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds from public.focus_segments where session_id=s.id and ended_at is not null;
 if s.status='focusing' then
  v_end:=least(v_end,s.active_segment_started_at+make_interval(secs=>(21600-v_closed_seconds)::double precision));
  update public.focus_segments set ended_at=v_end where session_id=s.id and ended_at is null;
 end if;
 select coalesce(sum(greatest(0,floor(extract(epoch from(v_end-started_at)))::int)),0)::int into v_uncertain
 from public.focus_connection_intervals where session_id=s.id and ended_at is null;
 update public.focus_connection_intervals set ended_at=v_end where session_id=s.id and ended_at is null and started_at<v_end;
 select least(21600,coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::int) into v_total from public.focus_segments where session_id=s.id and ended_at is not null;
 v_status:=case when v_total<300 then 'discarded'::public.focus_status else 'completed'::public.focus_status end;
 update public.focus_sessions set status=v_status,accumulated_focus_seconds=v_total,active_segment_started_at=null,paused_at=null,completed_at=v_end,
  completion_reason=p_reason,unconfirmed_connection_seconds=unconfirmed_connection_seconds+v_uncertain,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,null,'completed',v_end,jsonb_build_object('reason',p_reason)); return s.id;
end $$;

create function public.accept_proposal_if_ready(p_proposal_id uuid,p_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.goal_proposals%rowtype; bounds tstzrange; gid uuid;
begin
 select * into p from public.goal_proposals where id=p_proposal_id for update;
 if not found or p.status<>'pending' or exists(select 1 from public.goal_proposal_members where proposal_id=p.id and vote is distinct from 'accepted') then return null; end if;
 update public.goal_proposals set status='accepted',resolved_at=p_at where id=p.id;
 bounds:=public.next_goal_period((select timezone from public.spaces where id=p.space_id),p.period_type,p.created_at); gid:=gen_random_uuid();
 insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status)
 values(gid,p.id,p.space_id,p.goal_type,p.period_type,p.target_value,lower(bounds),upper(bounds),'scheduled');
 insert into public.goal_participants(goal_id,member_id) select gid,member_id from public.goal_proposal_members where proposal_id=p.id;
 return gid;
end $$;

create or replace function public.disable_member(p_space_id uuid,p_member_id uuid,p_idempotency_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); h text:=p_space_id::text||'|'||p_member_id::text; cached jsonb; m public.space_members%rowtype; sid uuid; result jsonb; r record; gid uuid; resolved jsonb:='[]'::jsonb;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 cached:=public.command_cached(a,p_idempotency_key,'disable_member',h); if cached is not null then return cached; end if;
 if not public.current_user_is_owner(p_space_id) then return public.api_error('NOT_SPACE_OWNER'); end if;
 select * into m from public.space_members where id=p_member_id and space_id=p_space_id for update;
 if not found then return public.api_error('MEMBER_NOT_FOUND'); end if; if m.role='owner' then return public.api_error('CANNOT_DISABLE_OWNER'); end if; if m.status='disabled' then return public.api_error('MEMBER_ALREADY_DISABLED'); end if;
 select id into sid from public.focus_sessions where member_id=m.id and status in ('focusing','paused') for update;
 if sid is not null then perform public.finish_focus_session(sid,now(),'member_disabled'); end if;
 update public.space_members set status='disabled',disabled_at=now(),disabled_by=a where id=m.id;
 for r in select gp.id from public.goal_proposals gp join public.goal_proposal_members gpm on gpm.proposal_id=gp.id where gp.space_id=p_space_id and gp.status='pending' and gpm.member_id=m.id for update of gp loop
  delete from public.goal_proposal_members where proposal_id=r.id and member_id=m.id; gid:=public.accept_proposal_if_ready(r.id,now());
  if gid is not null then resolved:=resolved||jsonb_build_array(jsonb_build_object('proposal_id',r.id,'goal_id',gid)); end if;
 end loop;
 result:=public.api_ok(jsonb_build_object('member',jsonb_build_object('member_id',m.id,'status','disabled','disabled_at',now()),
  'settled_session',case when sid is null then null else public.session_json(sid) end,'resolved_proposals',resolved));
 return public.store_command(a,p_idempotency_key,'disable_member',h,sid,result);
end $$;

create or replace function public.run_minute_maintenance() returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record; settled int:=0; uncertain int:=0; t timestamptz:=now(); goals jsonb;
begin
 for r in select id from public.focus_sessions where (status='paused' and paused_at+interval '15 minutes'<=t)
  or (status='focusing' and active_segment_started_at+make_interval(secs=>21600-accumulated_focus_seconds)<=t) order by started_at limit 100 for update skip locked
 loop perform public.settle_session(r.id,t); settled:=settled+1; end loop;
 for r in select id,last_seen_at from public.focus_sessions where status='focusing' and last_seen_at+interval '120 seconds'<=t order by last_seen_at limit 100 for update skip locked loop
  if not exists(select 1 from public.focus_connection_intervals where session_id=r.id and ended_at is null) then
   insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(r.id,r.last_seen_at+interval '120 seconds',r.last_seen_at);
   perform public.record_focus_event(r.id,null,'connection_unconfirmed',r.last_seen_at+interval '120 seconds'); uncertain:=uncertain+1;
   update public.focus_sessions set version=version+1 where id=r.id;
  end if;
 end loop;
 goals:=public.run_goal_maintenance(t); delete from public.focus_commands where created_at<t-interval '30 days';
 return jsonb_build_object('settled_sessions',settled,'new_unconfirmed_intervals',uncertain,'goal_maintenance',goals,'ran_at',t);
end $$;

revoke all on function public.accept_proposal_if_ready(uuid,timestamptz) from public;
