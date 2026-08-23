begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

select ok('life'=any(enum_range(null::public.focus_category)::text[]),'life is a supported focus category');
select is((select count(*)::integer from private.achievement_strategy_catalog),30,'catalog includes the life achievement');
select is((select stage_thresholds#>>'{0,title}' from private.achievement_strategy_catalog where key='orderly_living'),'井井有条','life achievement has the approved title');
select is((select stage_thresholds#>>'{0,threshold}' from private.achievement_strategy_catalog where key='orderly_living'),'10','life achievement unlocks at ten sessions');
select is((select icon from private.achievement_strategy_catalog where key='orderly_living'),'cog','life achievement uses Cog');
select is((select tier_policy->>'tier' from private.achievement_strategy_catalog where key='orderly_living'),'gold','life achievement is gold');

insert into auth.users(id) values('00000000-0000-0000-0000-000000000311');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000311','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values(
  '10000000-0000-0000-0000-000000000311','Life achievement',
  '00000000-0000-0000-0000-000000000311','UTC','life-achievement'
);
insert into public.space_members(id,space_id,user_id,display_name,role) values(
  '20000000-0000-0000-0000-000000000311','10000000-0000-0000-0000-000000000311',
  '00000000-0000-0000-0000-000000000311','Life owner','owner'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000311',true);
select is(public.acknowledge_focus_health_policy(2,'max_focus_seconds=14400')#>>'{data,acknowledged_version}','2','the production health policy contract is acknowledged');
select is(
  public.start_focus('10000000-0000-0000-0000-000000000311','Life RPC','life','UTC',2,'max_focus_seconds=14400','30000000-0000-0000-0000-000000000311')#>>'{data,session,category}',
  'life','start_focus accepts life'
);
select lives_ok(
  $$select public.end_focus((select id from public.focus_sessions where task_name='Life RPC'),'30000000-0000-0000-0000-000000000312')$$,
  'the RPC fixture can settle'
);
reset role;

select set_config('youjian.achievement_source','scheduled_maintenance',true);
update public.focus_sessions set status='discarded',active_segment_started_at=null,completed_at=now(),completion_reason='manual_end'
where user_id='00000000-0000-0000-0000-000000000311' and status in('focusing','paused');

do $$
declare enabled timestamptz; sid uuid; started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='orderly_living';

  sid:=gen_random_uuid(); started:=enabled-interval '1 minute';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Before activation','life','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;

  sid:=gen_random_uuid(); started:=enabled+interval '30 seconds';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Discarded life','life','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '2 minutes');
  update public.focus_sessions set status='discarded',accumulated_focus_seconds=120,active_segment_started_at=null,completed_at=started+interval '2 minutes',completion_reason='manual_end' where id=sid;

  sid:=gen_random_uuid(); started:=enabled+interval '45 seconds';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Zero life','life','focusing',started,started,started,'UTC');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=0,active_segment_started_at=null,completed_at=started,completion_reason='manual_end' where id=sid;

  for i in 1..9 loop
    sid:=gen_random_uuid(); started:=enabled+make_interval(mins=>i);
    insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
    values(sid,'10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Life '||i,'life','focusing',started,started,started,'UTC');
    insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
    update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
  end loop;
end $$;

select is((select count(*)::integer from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000311' and achievement_type='orderly_living'),0,'pre-activation, discarded, zero-second, and first nine valid sessions do not unlock the achievement');

do $$
declare enabled timestamptz; sid uuid:=gen_random_uuid(); started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='orderly_living';
  started:=enabled+interval '10 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Life 10','life','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
end $$;

select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000311' and achievement_type='orderly_living'),1,'the tenth qualifying life session unlocks once');
select is((select metadata->>'metric_value' from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000311' and achievement_type='orderly_living'),'10','the award records the qualifying category count');
select is((select metadata->>'category' from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000311' and achievement_type='orderly_living'),'life','the award records the final life category');
select ok((select notification_eligible from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000311' and achievement_type='orderly_living'),'the first unlock is notification eligible');

do $$
declare enabled timestamptz; sid uuid; started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='orderly_living';

  sid:=gen_random_uuid(); started:=enabled+interval '11 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000311','00000000-0000-0000-0000-000000000311','20000000-0000-0000-0000-000000000311','Life 11','life','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;

end $$;

select is((select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000311' and achievement_type='orderly_living'),1,'the eleventh valid session creates no additional award');

select * from finish();
rollback;
