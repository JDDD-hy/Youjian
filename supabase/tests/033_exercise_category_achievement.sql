begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

select is((select count(*)::integer from private.achievement_strategy_catalog),31,'catalog includes the exercise achievement');
select is((select stage_thresholds#>>'{0,title}' from private.achievement_strategy_catalog where key='exercise_vitality'),'生龙活虎','exercise achievement has the approved title');
select is((select stage_thresholds#>>'{0,threshold}' from private.achievement_strategy_catalog where key='exercise_vitality'),'10','exercise achievement unlocks at ten sessions');
select is((select icon from private.achievement_strategy_catalog where key='exercise_vitality'),'dumbbell','exercise achievement uses Dumbbell');
select is((select tier_policy->>'tier' from private.achievement_strategy_catalog where key='exercise_vitality'),'gold','exercise achievement is gold');

insert into auth.users(id) values('00000000-0000-0000-0000-000000000331');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000331','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values(
  '10000000-0000-0000-0000-000000000331','Exercise achievement',
  '00000000-0000-0000-0000-000000000331','UTC','exercise-achievement'
);
insert into public.space_members(id,space_id,user_id,display_name,role) values(
  '20000000-0000-0000-0000-000000000331','10000000-0000-0000-0000-000000000331',
  '00000000-0000-0000-0000-000000000331','Exercise owner','owner'
);

select set_config('youjian.achievement_source','scheduled_maintenance',true);

do $$
declare enabled timestamptz; sid uuid; started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='exercise_vitality';

  sid:=gen_random_uuid(); started:=enabled-interval '1 minute';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000331','00000000-0000-0000-0000-000000000331','20000000-0000-0000-0000-000000000331','Before activation','exercise','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;

  sid:=gen_random_uuid(); started:=enabled+interval '30 seconds';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000331','00000000-0000-0000-0000-000000000331','20000000-0000-0000-0000-000000000331','Discarded exercise','exercise','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '2 minutes');
  update public.focus_sessions set status='discarded',accumulated_focus_seconds=120,active_segment_started_at=null,completed_at=started+interval '2 minutes',completion_reason='manual_end' where id=sid;

  sid:=gen_random_uuid(); started:=enabled+interval '45 seconds';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000331','00000000-0000-0000-0000-000000000331','20000000-0000-0000-0000-000000000331','Zero exercise','exercise','focusing',started,started,started,'UTC');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=0,active_segment_started_at=null,completed_at=started,completion_reason='manual_end' where id=sid;

  for i in 1..9 loop
    sid:=gen_random_uuid(); started:=enabled+make_interval(mins=>i);
    insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
    values(sid,'10000000-0000-0000-0000-000000000331','00000000-0000-0000-0000-000000000331','20000000-0000-0000-0000-000000000331','Exercise '||i,'exercise','focusing',started,started,started,'UTC');
    insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
    update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
  end loop;
end $$;

select is((select count(*)::integer from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),0,'pre-activation, discarded, zero-second, and first nine valid sessions do not unlock the achievement');

do $$
declare enabled timestamptz; sid uuid:=gen_random_uuid(); started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='exercise_vitality';
  started:=enabled+interval '10 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000331','00000000-0000-0000-0000-000000000331','20000000-0000-0000-0000-000000000331','Exercise 10','exercise','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
end $$;

select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),1,'the tenth qualifying exercise session unlocks once');
select is((select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),'gold','the unlocked achievement has the approved tier');
select is((select metadata->>'metric_value' from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),'10','the award records the qualifying category count');
select is((select metadata->>'category' from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),'exercise','the award records the final exercise category');
select ok((select notification_eligible from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),'the first unlock is notification eligible');

do $$
declare enabled timestamptz; sid uuid:=gen_random_uuid(); started timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='exercise_vitality';
  started:=enabled+interval '11 minutes';
  insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,started_at,last_seen_at,timezone_snapshot)
  values(sid,'10000000-0000-0000-0000-000000000331','00000000-0000-0000-0000-000000000331','20000000-0000-0000-0000-000000000331','Exercise 11','exercise','focusing',started,started,started,'UTC');
  insert into public.focus_segments(session_id,started_at,ended_at) values(sid,started,started+interval '10 minutes');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=600,active_segment_started_at=null,completed_at=started+interval '10 minutes',completion_reason='manual_end' where id=sid;
end $$;

select is((select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),1,'the eleventh valid session creates no additional award');
select is((select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000331' and achievement_type='exercise_vitality'),1,'the once-only achievement remains capped at one');

select * from finish();
rollback;
