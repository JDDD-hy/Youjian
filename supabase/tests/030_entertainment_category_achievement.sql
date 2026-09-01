begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

select ok(
  'entertainment'=any(enum_range(null::public.focus_category)::text[]),
  'entertainment is a supported focus category'
);
select is(
  (select count(*)::integer from private.achievement_strategy_catalog),
  31,
  'catalog includes the entertainment achievement'
);
select is(
  (select stage_thresholds#>>'{0,title}' from private.achievement_strategy_catalog where key='joyful_pursuit'),
  '乐在其中',
  'entertainment achievement has the approved title'
);
select is(
  (select stage_thresholds#>>'{0,threshold}' from private.achievement_strategy_catalog where key='joyful_pursuit'),
  '10',
  'entertainment achievement unlocks at ten sessions'
);
select is(
  (select icon from private.achievement_strategy_catalog where key='joyful_pursuit'),
  'gamepad_2',
  'entertainment achievement uses Gamepad 2'
);
select is(
  (select tier_policy->>'tier' from private.achievement_strategy_catalog where key='joyful_pursuit'),
  'gold',
  'entertainment achievement is gold'
);

insert into auth.users(id) values('00000000-0000-0000-0000-000000000301');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000301','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values(
  '10000000-0000-0000-0000-000000000301','Entertainment achievement',
  '00000000-0000-0000-0000-000000000301','UTC','entertainment-achievement'
);
insert into public.space_members(id,space_id,user_id,display_name,role) values(
  '20000000-0000-0000-0000-000000000301','10000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000301','Entertainment owner','owner'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000301',true);
select is(
  public.acknowledge_focus_health_policy(2,'max_focus_seconds=14400')#>>'{data,acknowledged_version}',
  '2',
  'the production health policy contract is acknowledged'
);
select is(
  public.start_focus(
    '10000000-0000-0000-0000-000000000301','Entertainment RPC','entertainment','UTC',
    2,'max_focus_seconds=14400',
    '30000000-0000-0000-0000-000000000301'
  )#>>'{data,session,category}',
  'entertainment',
  'start_focus accepts entertainment'
);
select is(
  public.update_focus_task(
    (select id from public.focus_sessions where task_name='Entertainment RPC'),
    'Entertainment RPC revised','entertainment','30000000-0000-0000-0000-000000000302'
  )#>>'{data,session,category}',
  'entertainment',
  'update_focus_task accepts entertainment'
);
select lives_ok(
  $$select public.end_focus(
    (select id from public.focus_sessions where task_name='Entertainment RPC revised'),
    '30000000-0000-0000-0000-000000000303'
  )$$,
  'the RPC fixture can settle'
);
reset role;

select set_config('youjian.achievement_source','scheduled_maintenance',true);
update public.focus_sessions
set status='discarded',active_segment_started_at=null,completed_at=now(),completion_reason='manual_end'
where user_id='00000000-0000-0000-0000-000000000301'
  and status in('focusing','paused');

do $$
declare
  enabled timestamptz;
  sid uuid;
  started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='joyful_pursuit';

  sid:=gen_random_uuid(); started:=enabled-interval '1 minute';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000301','Before activation','entertainment','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;

  for i in 1..9 loop
    sid:=gen_random_uuid(); started:=enabled+make_interval(mins=>i);
    insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
    values(sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000301','Entertainment '||i,'entertainment','focusing',started,started,started,'UTC');
    insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
    update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
  end loop;
end $$;

select is(
  (select count(*)::integer from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  0,
  'pre-activation and first nine sessions do not unlock the achievement'
);

do $$
declare enabled timestamptz; sid uuid:=gen_random_uuid(); started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='joyful_pursuit';
  started:=enabled+interval '10 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000301','Entertainment 10','entertainment','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
end $$;

select is(
  (select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  1,
  'the tenth qualifying entertainment session unlocks once'
);
select is(
  (select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  'gold',
  'the unlocked achievement has the approved tier'
);
select is(
  (select metadata->>'metric_value' from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  '10',
  'the award records the qualifying category count'
);
select is(
  (select metadata->>'category' from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  'entertainment',
  'the award records the final entertainment category'
);
select ok(
  (select notification_eligible from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  'the first unlock is notification eligible'
);

do $$
declare enabled timestamptz; sid uuid:=gen_random_uuid(); started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='joyful_pursuit';
  started:=enabled+interval '11 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000301','Entertainment 11','entertainment','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;

  sid:=gen_random_uuid(); started:=enabled+interval '12 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000301','Discarded entertainment','entertainment','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '2 minutes');
  update public.focus_sessions set status='discarded',accumulated_focus_seconds=120,active_segment_started_at=null,completed_at=started+interval '2 minutes',completion_reason='manual_end' where id=sid;

  sid:=gen_random_uuid(); started:=enabled+interval '13 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000301','20000000-0000-0000-0000-000000000301','Zero entertainment','entertainment','focusing',started,started,started,'UTC');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=0,active_segment_started_at=null,completed_at=started,completion_reason='manual_end' where id=sid;
end $$;

select is(
  (select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000301' and achievement_type='joyful_pursuit'),
  1,
  'later, discarded, and zero-second sessions create no additional award'
);

select * from finish();
rollback;
