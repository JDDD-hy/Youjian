create or replace function public.finish_focus_session(p_session_id uuid,p_at timestamptz,p_reason public.completion_reason) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; v_end timestamptz; v_total int; v_status public.focus_status; v_uncertain int:=0; v_closed_seconds numeric:=0;
begin
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found or s.status in('completed','discarded') then return p_session_id; end if;
 v_end:=case when s.status='paused' then s.paused_at else p_at end;
 select coalesce(sum(extract(epoch from(ended_at-started_at))),0) into v_closed_seconds from public.focus_segments where session_id=s.id and ended_at is not null;
 if s.status='focusing' then
  v_end:=least(v_end,s.active_segment_started_at+make_interval(secs=>(21600-v_closed_seconds)::double precision));
  update public.focus_segments set ended_at=v_end where session_id=s.id and ended_at is null;
 end if;
 select coalesce(floor(sum(extract(epoch from(v_end-started_at))) filter(where started_at<v_end)),0)::int into v_uncertain
 from public.focus_connection_intervals where session_id=s.id and ended_at is null;
 update public.focus_connection_intervals set ended_at=v_end where session_id=s.id and ended_at is null and started_at<v_end;
 delete from public.focus_connection_intervals where session_id=s.id and ended_at is null and started_at>=v_end;
 select least(21600,coalesce(floor(sum(extract(epoch from(ended_at-started_at)))),0)::int) into v_total from public.focus_segments where session_id=s.id and ended_at is not null;
 v_status:=case when v_total<300 then 'discarded'::public.focus_status else 'completed'::public.focus_status end;
 update public.focus_sessions set status=v_status,accumulated_focus_seconds=v_total,active_segment_started_at=null,paused_at=null,completed_at=v_end,
  completion_reason=p_reason,unconfirmed_connection_seconds=unconfirmed_connection_seconds+v_uncertain,version=version+1 where id=s.id;
 perform public.record_focus_event(s.id,null,'completed',v_end,jsonb_build_object('reason',p_reason)); return s.id;
end $$;

create or replace function public.credited_seconds_for_day(p_space_id uuid,p_user_id uuid,p_local_date date,p_timezone text) returns integer
language sql stable security definer set search_path='' as $$
 with bounds as(select p_local_date::timestamp at time zone p_timezone lo,(p_local_date+1)::timestamp at time zone p_timezone hi)
 select coalesce(floor(sum(extract(epoch from(least(g.ended_at,b.hi)-greatest(g.started_at,b.lo))))),0)::int
 from bounds b join public.focus_segments g on g.ended_at>b.lo and g.started_at<b.hi
 join public.focus_sessions s on s.id=g.session_id where s.space_id=p_space_id and s.user_id=p_user_id and s.status='completed'
$$;

create or replace function public.current_streak_days(p_space_id uuid,p_user_id uuid,p_timezone text,p_at timestamptz default now()) returns integer
language sql stable security definer set search_path='' as $$
 with settings as(select(p_at at time zone p_timezone)::date current_day,daily_checkin_target_minutes::bigint*60 target from public.spaces where id=p_space_id),
 daily as(
  select day_value::date local_date,floor(sum(extract(epoch from(least(g.ended_at,(day_value::date+1)::timestamp at time zone p_timezone)-greatest(g.started_at,day_value::date::timestamp at time zone p_timezone)))))::bigint as seconds
  from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
  cross join lateral generate_series(((g.started_at at time zone p_timezone)::date)::timestamp,(((g.ended_at-interval '1 microsecond') at time zone p_timezone)::date)::timestamp,interval '1 day') day_value
  where s.space_id=p_space_id and s.user_id=p_user_id and s.status='completed' and g.ended_at is not null group by day_value::date
 ), anchor as(
  select case when coalesce((select seconds from daily where local_date=settings.current_day),0)>=settings.target then settings.current_day else settings.current_day-1 end local_date,settings.target from settings
 ), qualifying as(
  select daily.local_date,row_number() over(order by daily.local_date desc) position from daily cross join anchor where daily.seconds>=anchor.target and daily.local_date<=anchor.local_date
 )
 select coalesce(count(*) filter(where qualifying.local_date=anchor.local_date-(qualifying.position::integer-1)),0)::integer from anchor left join qualifying on true
$$;

create or replace function public.goal_progress_json(p_goal_id uuid,p_at timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g public.goals%rowtype; tz text; seconds int; members jsonb; done boolean; shared_days int; target_seconds int;
begin
 select * into g from public.goals where id=p_goal_id; select timezone,daily_checkin_target_minutes*60 into tz,target_seconds from public.spaces where id=g.space_id;
 if g.goal_type='group_total_minutes' then
  select coalesce(floor(sum(extract(epoch from(least(fs.ended_at,g.ends_at)-greatest(fs.started_at,g.starts_at))))),0)::int into seconds
  from public.focus_segments fs join public.focus_sessions s on s.id=fs.session_id join public.goal_participants gp on gp.member_id=s.member_id and gp.goal_id=g.id
  where s.status='completed' and fs.ended_at>g.starts_at and fs.started_at<least(g.ends_at,p_at);
  return jsonb_build_object('credited_value',seconds/60,'completed',seconds>=g.target_value*60,'members',null);
 elsif g.goal_type='per_member_minutes' then
  with vals as(
   select m.id,m.display_name,coalesce(floor(sum(extract(epoch from(least(fs.ended_at,g.ends_at)-greatest(fs.started_at,g.starts_at)))) filter(where s.status='completed')),0)::int sec
   from public.goal_participants gp join public.space_members m on m.id=gp.member_id left join public.focus_sessions s on s.member_id=m.id
   left join public.focus_segments fs on fs.session_id=s.id and fs.ended_at>g.starts_at and fs.started_at<least(g.ends_at,p_at)
   where gp.goal_id=g.id group by m.id,m.display_name
  ) select coalesce(jsonb_agg(jsonb_build_object('member_id',id,'display_name',display_name,'credited_value',sec/60,'completed',sec>=g.target_value*60) order by display_name),'[]'),bool_and(sec>=g.target_value*60) into members,done from vals;
  return jsonb_build_object('credited_value',null,'completed',coalesce(done,false),'members',members);
 else
  with local_days as(select d::date local_date from generate_series((g.starts_at at time zone tz)::date,((least(g.ends_at,p_at)-interval '1 microsecond') at time zone tz)::date,interval '1 day') d),
  qualifying as(select d.local_date from local_days d where not exists(select 1 from public.goal_participants gp join public.space_members m on m.id=gp.member_id where gp.goal_id=g.id and public.credited_seconds_for_day(g.space_id,m.user_id,d.local_date,tz)<target_seconds))
  select count(*)::int into shared_days from qualifying;
  return jsonb_build_object('credited_value',shared_days,'completed',shared_days>=g.target_value,'members',null);
 end if;
end $$;

create or replace function public.accept_proposal_if_ready(p_proposal_id uuid,p_at timestamptz default now()) returns uuid
language plpgsql security definer set search_path='' as $$
declare p public.goal_proposals%rowtype; bounds tstzrange; gid uuid;
begin
 select * into p from public.goal_proposals where id=p_proposal_id for update;
 if not found or p.status<>'pending' or exists(select 1 from public.goal_proposal_members where proposal_id=p.id and vote is distinct from 'accepted') then return null; end if;
 bounds:=public.next_goal_period((select timezone from public.spaces where id=p.space_id),p.period_type,p_at);
 update public.goal_proposals set status='accepted',resolved_at=p_at,effective_period_start=lower(bounds) where id=p.id;
 gid:=gen_random_uuid(); insert into public.goals(id,source_proposal_id,space_id,goal_type,period_type,target_value,starts_at,ends_at,status)
 values(gid,p.id,p.space_id,p.goal_type,p.period_type,p.target_value,lower(bounds),upper(bounds),'scheduled');
 insert into public.goal_participants(goal_id,member_id) select gid,member_id from public.goal_proposal_members where proposal_id=p.id; return gid;
end $$;

create function private.json_contains_sensitive_key(p_value jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare item record; element jsonb;
begin
 if jsonb_typeof(p_value)='object' then
  for item in select key,value from jsonb_each(p_value) loop
   if lower(item.key)~'(token|invite|task|nickname|display.?name|email|authorization)' or private.json_contains_sensitive_key(item.value) then return true; end if;
  end loop;
 elsif jsonb_typeof(p_value)='array' then
  for element in select value from jsonb_array_elements(p_value) loop if private.json_contains_sensitive_key(element) then return true; end if; end loop;
 end if;
 return false;
end $$;
revoke all on function private.json_contains_sensitive_key(jsonb) from public,anon,authenticated;

create or replace function public.report_client_error(p_error_code text,p_route text default null,p_metadata jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); rid uuid;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 if p_error_code is null or p_error_code!~'^[A-Z0-9_.-]{1,80}$' or p_route is not null and(char_length(p_route)>200 or p_route~*'(/invite/[^/?#]+|[?&](token|authorization|email)=)') or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then return public.api_error('INVALID_ERROR_REPORT'); end if;
 if private.json_contains_sensitive_key(p_metadata) then return public.api_error('SENSITIVE_METADATA_REJECTED'); end if;
 if octet_length(p_metadata::text)>4096 then return public.api_error('INVALID_ERROR_REPORT'); end if;
 insert into private.client_error_reports(actor_id,error_code,route,metadata) values(a,p_error_code,p_route,p_metadata) returning id into rid;
 return public.api_ok(jsonb_build_object('report_id',rid));
end $$;

create or replace function public.list_focus_history(p_space_id uuid,p_view text,p_period_start timestamptz,p_period_end timestamptz,p_limit integer default 30,p_cursor text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); cursor_time timestamptz; cursor_id uuid; items jsonb; next_cursor text;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_view not in('mine','space') then return public.api_error('INVALID_VIEW'); end if;
 if p_limit is null or p_limit<1 or p_limit>100 or p_period_start is null or p_period_end is null or p_period_end<=p_period_start or p_period_end-p_period_start>interval '366 days' then return public.api_error('INVALID_RANGE'); end if;
 if p_cursor is not null then begin cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz; cursor_id:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2)::uuid; exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
 with rows as(
  select s.*,m.display_name,row_number() over(order by s.completed_at desc,s.id desc) rn from public.focus_sessions s join public.space_members m on m.id=s.member_id
  where s.space_id=p_space_id and s.status in('completed','discarded') and s.completed_at>=p_period_start and s.completed_at<p_period_end and(p_view='space' or s.user_id=a) and(p_cursor is null or(s.completed_at,s.id)<(cursor_time,cursor_id))
  order by s.completed_at desc,s.id desc limit p_limit+1
 ),chosen as(select * from rows where rn<=p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('session_id',id,'member',jsonb_build_object('member_id',member_id,'display_name',display_name),'task_name',task_name,'category',category,'started_at',started_at,'completed_at',completed_at,'credited_focus_seconds',accumulated_focus_seconds,'status',status,'completion_reason',completion_reason,'counts_toward_stats',status='completed','unconfirmed_connection_seconds',unconfirmed_connection_seconds) order by completed_at desc,id desc),'[]'),
 case when(select count(*) from rows)>p_limit then(select encode(convert_to(completed_at::text||'|'||id::text,'UTF8'),'base64') from chosen order by completed_at,id limit 1) end into items,next_cursor from chosen;
 return public.api_ok(jsonb_build_object('items',items,'next_cursor',next_cursor));
end $$;

revoke all on function public.finish_focus_session(uuid,timestamptz,public.completion_reason),public.credited_seconds_for_day(uuid,uuid,date,text),
 public.current_streak_days(uuid,uuid,text,timestamptz),public.goal_progress_json(uuid,timestamptz),public.accept_proposal_if_ready(uuid,timestamptz) from public;
