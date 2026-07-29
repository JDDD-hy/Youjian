create function public.credited_seconds_for_day(p_space_id uuid,p_user_id uuid,p_local_date date,p_timezone text) returns integer
language sql stable security definer set search_path='' as $$
 with bounds as (
   select p_local_date::timestamp at time zone p_timezone as lo,
          (p_local_date+1)::timestamp at time zone p_timezone as hi
 )
 select coalesce(sum(floor(extract(epoch from (least(g.ended_at,b.hi)-greatest(g.started_at,b.lo))))),0)::int
 from bounds b join public.focus_segments g on g.ended_at>b.lo and g.started_at<b.hi
 join public.focus_sessions s on s.id=g.session_id
 where s.space_id=p_space_id and s.user_id=p_user_id and s.status='completed'
$$;

create function public.current_streak_days(p_space_id uuid,p_user_id uuid,p_timezone text,p_at timestamptz default now()) returns integer
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p_at at time zone p_timezone)::date; target int; streak int:=0;
begin
 select daily_checkin_target_minutes*60 into target from public.spaces where id=p_space_id;
 if public.credited_seconds_for_day(p_space_id,p_user_id,d,p_timezone)<target then d:=d-1; end if;
 while public.credited_seconds_for_day(p_space_id,p_user_id,d,p_timezone)>=target loop streak:=streak+1; d:=d-1; end loop;
 return streak;
end $$;

create function public.get_stats_summary(p_space_id uuid,p_view text,p_period text,p_anchor_local_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); tz text; local_start date; local_end date; utc_start timestamptz; utc_end timestamptz;
 target int; days jsonb; total int; checkins int; sessions int;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_view not in ('mine','space') then return public.api_error('INVALID_VIEW'); end if;
 if p_period not in ('daily','weekly','monthly') then return public.api_error('INVALID_PERIOD'); end if;
 if p_anchor_local_date is null or p_anchor_local_date<date '2000-01-01' or p_anchor_local_date>date '2100-12-31' then return public.api_error('INVALID_DATE'); end if;
 if p_view='mine' then select timezone into tz from public.profiles where id=a; else select timezone into tz from public.spaces where id=p_space_id; end if;
 if p_period='daily' then local_start:=p_anchor_local_date; local_end:=local_start+1;
 elsif p_period='weekly' then local_start:=date_trunc('week',p_anchor_local_date::timestamp)::date; local_end:=local_start+7;
 else local_start:=date_trunc('month',p_anchor_local_date::timestamp)::date; local_end:=(local_start+interval '1 month')::date; end if;
 utc_start:=local_start::timestamp at time zone tz; utc_end:=local_end::timestamp at time zone tz;
 select daily_checkin_target_minutes*60 into target from public.spaces where id=p_space_id;
 with day_values as (
   select d::date local_date,
     case when p_view='mine' then public.credited_seconds_for_day(p_space_id,a,d::date,tz)
     else coalesce((select sum(public.credited_seconds_for_day(p_space_id,m.user_id,d::date,tz)) from public.space_members m where m.space_id=p_space_id),0)::int end seconds
   from generate_series(local_start,local_end-1,interval '1 day') d
 ) select coalesce(jsonb_agg(jsonb_build_object('local_date',local_date,'credited_focus_seconds',seconds,'checkin_completed',seconds>=target) order by local_date),'[]'),
   coalesce(sum(seconds),0)::int,count(*) filter(where seconds>=target)::int into days,total,checkins from day_values;
 select count(distinct s.id)::int into sessions from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
 where s.space_id=p_space_id and s.status='completed' and g.ended_at>utc_start and g.started_at<utc_end and (p_view='space' or s.user_id=a);
 return public.api_ok(jsonb_build_object('view',p_view,'period',p_period,'timezone',tz,'period_start',utc_start,'period_end',utc_end,
  'credited_focus_seconds',total,'valid_session_count',sessions,'checkin_day_count',checkins,'days',days));
end $$;

create function public.list_focus_history(p_space_id uuid,p_view text,p_period_start timestamptz,p_period_end timestamptz,
 p_limit integer default 30,p_cursor text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); cursor_time timestamptz; cursor_id uuid; items jsonb; next_cursor text;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 if p_view not in ('mine','space') then return public.api_error('INVALID_VIEW'); end if;
 if p_limit is null or p_limit<1 or p_limit>100 or p_period_start is null or p_period_end is null or p_period_end<=p_period_start then return public.api_error('INVALID_RANGE'); end if;
 if p_cursor is not null then
   begin
    cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz;
    cursor_id:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2)::uuid;
   exception when others then return public.api_error('INVALID_CURSOR'); end;
 end if;
 with rows as (
  select s.*,m.display_name,row_number() over(order by s.completed_at desc,s.id desc) rn
  from public.focus_sessions s join public.space_members m on m.id=s.member_id
  where s.space_id=p_space_id and s.status in ('completed','discarded') and s.completed_at>=p_period_start and s.completed_at<p_period_end
   and (p_view='space' or s.user_id=a) and (p_cursor is null or (s.completed_at,s.id)<(cursor_time,cursor_id))
  order by s.completed_at desc,s.id desc limit p_limit+1
 ), chosen as (select * from rows where rn<=p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('session_id',id,'member',jsonb_build_object('member_id',member_id,'display_name',display_name),
   'task_name',task_name,'category',category,'started_at',started_at,'completed_at',completed_at,'credited_focus_seconds',accumulated_focus_seconds,
   'status',status,'completion_reason',completion_reason,'counts_toward_stats',status='completed','unconfirmed_connection_seconds',unconfirmed_connection_seconds)
   order by completed_at desc,id desc),'[]'::jsonb),
   case when (select count(*) from rows)>p_limit then (select encode(convert_to(completed_at::text||'|'||id::text,'UTF8'),'base64') from chosen order by completed_at,id limit 1) end
 into items,next_cursor from chosen;
 return public.api_ok(jsonb_build_object('items',items,'next_cursor',next_cursor));
end $$;

create function public.get_focus_session_detail(p_session_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; segments jsonb; intervals jsonb;
begin
 select * into s from public.focus_sessions where id=p_session_id;
 if not found or not public.current_user_is_active_member(s.space_id) then return public.api_error('SESSION_NOT_FOUND'); end if;
 select coalesce(jsonb_agg(jsonb_build_object('started_at',started_at,'ended_at',ended_at) order by started_at),'[]') into segments from public.focus_segments where session_id=s.id;
 select coalesce(jsonb_agg(jsonb_build_object('started_at',started_at,'ended_at',ended_at,'detected_from_last_seen_at',detected_from_last_seen_at) order by started_at),'[]') into intervals from public.focus_connection_intervals where session_id=s.id;
 return public.api_ok(jsonb_build_object('session',public.session_json(s.id),'segments',segments,'connection_unconfirmed_intervals',intervals,
   'settlement',jsonb_build_object('reason',s.completion_reason,'counts_toward_stats',case when s.status='completed' then true when s.status='discarded' then false end)));
end $$;

create or replace function public.heartbeat_focus(p_session_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); s public.focus_sessions%rowtype; reconnect boolean:=false; interval_start timestamptz; added int:=0;
begin
 if a is null then return public.api_error('AUTH_REQUIRED'); end if;
 select * into s from public.focus_sessions where id=p_session_id for update;
 if not found then return public.api_error('SESSION_NOT_FOUND'); end if; if s.user_id<>a then return public.api_error('SESSION_NOT_OWNED'); end if;
 perform public.settle_session(s.id,now()); select * into s from public.focus_sessions where id=s.id;
 if s.status='focusing' then
   reconnect:=now()-s.last_seen_at>interval '120 seconds';
   if reconnect then
    interval_start:=s.last_seen_at+interval '120 seconds';
    select started_at into interval_start from public.focus_connection_intervals where session_id=s.id and ended_at is null for update;
    if interval_start is null then
      interval_start:=s.last_seen_at+interval '120 seconds';
      insert into public.focus_connection_intervals(session_id,started_at,detected_from_last_seen_at) values(s.id,interval_start,s.last_seen_at);
    end if;
    added:=greatest(0,floor(extract(epoch from(now()-interval_start)))::int);
    update public.focus_connection_intervals set ended_at=now() where session_id=s.id and ended_at is null;
    perform public.record_focus_event(s.id,a,'reconnected');
   end if;
   update public.focus_sessions set last_seen_at=now(),unconfirmed_connection_seconds=unconfirmed_connection_seconds+added,version=version+1 where id=s.id;
 end if;
 return public.api_ok(jsonb_build_object('session',public.session_json(s.id),'connection_reconfirmed',reconnect));
end $$;

create function public.get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=auth.uid(); sp public.spaces%rowtype; me public.space_members%rowtype; my_sid uuid; friends jsonb; today_seconds int; streak int;
 today_date date; profile_tz text; active_count int;
begin
 if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
 select * into sp from public.spaces where id=p_space_id; select * into me from public.space_members where space_id=p_space_id and user_id=a and status='active';
 select timezone into profile_tz from public.profiles where id=a;
 perform public.settle_session(id,now()) from public.focus_sessions where space_id=p_space_id and status in ('focusing','paused');
 perform public.run_minute_maintenance();
 select id into my_sid from public.focus_sessions where user_id=a and status in ('focusing','paused');
 select count(*) into active_count from public.space_members where space_id=p_space_id and status='active';
 select coalesce(jsonb_agg(jsonb_build_object('member_id',m.id,'display_name',m.display_name,'session_id',s.id,'task_name',s.task_name,'category',s.category,
  'status',s.status,'accumulated_focus_seconds',s.accumulated_focus_seconds,'active_segment_started_at',s.active_segment_started_at,
  'connection',jsonb_build_object('status',case when now()-s.last_seen_at>interval '120 seconds' then 'unconfirmed' else 'connected' end,'last_seen_at',s.last_seen_at)) order by m.joined_at),'[]')
 into friends from public.focus_sessions s join public.space_members m on m.id=s.member_id where s.space_id=p_space_id and s.user_id<>a and s.status='focusing' and m.status='active';
 today_date:=(now() at time zone profile_tz)::date; today_seconds:=public.credited_seconds_for_day(p_space_id,a,today_date,profile_tz);
 streak:=public.current_streak_days(p_space_id,a,profile_tz);
 return public.api_ok(jsonb_build_object('space',jsonb_build_object('id',sp.id,'name',sp.name,'timezone',sp.timezone,'active_member_count',active_count,
  'member_limit',sp.member_limit,'daily_checkin_target_minutes',sp.daily_checkin_target_minutes),
  'me',jsonb_build_object('member_id',me.id,'display_name',me.display_name,'role',me.role,'profile_timezone',profile_tz),
  'my_session',case when my_sid is null then null else public.session_json(my_sid) end,'focusing_members',friends,
  'today',jsonb_build_object('credited_focus_seconds',today_seconds,'checkin_target_seconds',sp.daily_checkin_target_minutes*60,
    'checkin_completed',today_seconds>=sp.daily_checkin_target_minutes*60,'current_streak_days',streak),
  'active_goal_summary',null,'unseen_achievement',(select jsonb_build_object('achievement_id',ac.id,'achievement_type',ac.achievement_type,'earned_at',ac.earned_at,'metadata',ac.metadata)
    from public.achievements ac left join public.achievement_reads ar on ar.achievement_id=ac.id and ar.member_id=me.id
    where ac.space_id=p_space_id and ar.achievement_id is null order by ac.earned_at limit 1)));
end $$;

revoke all on function public.credited_seconds_for_day(uuid,uuid,date,text), public.current_streak_days(uuid,uuid,text,timestamptz) from public;
grant execute on function public.get_home_snapshot(uuid), public.get_stats_summary(uuid,text,text,date),
 public.list_focus_history(uuid,text,timestamptz,timestamptz,integer,text), public.get_focus_session_detail(uuid) to authenticated;
