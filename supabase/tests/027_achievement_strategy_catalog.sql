begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

select is(
  (select count(*)::integer from private.achievement_strategy_catalog),
  28,
  'catalog contains the existing and newly-added strategies'
);
select is(
  (select tier_policy->'tiers'->>'1' from private.achievement_strategy_catalog where key='global_timezones'),
  'silver',
  'global two-timezone stage is silver'
);
select is(
  (select tier_policy->'tiers'->>'2' from private.achievement_strategy_catalog where key='global_timezones'),
  'gold',
  'global four-timezone stage is gold'
);
select is(
  (select stage_thresholds->0->>'icon' from private.achievement_strategy_catalog where key='global_timezones'),
  'plane',
  'global first stage uses Plane'
);
select is(
  (select stage_thresholds->1->>'icon' from private.achievement_strategy_catalog where key='global_timezones'),
  'earth',
  'global second stage uses Earth'
);
select is(
  (select icon from private.achievement_strategy_catalog where key='task_polisher'),
  'wand_sparkles',
  'new task achievement uses Wand Sparkles'
);
select is(
  (select stage_thresholds->0->>'threshold' from private.achievement_strategy_catalog where key='focus_10000_hours'),
  '600000',
  'ten thousand hours is stored as six hundred thousand minutes'
);

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000271'),
  ('00000000-0000-0000-0000-000000000272');
insert into public.profiles(id,timezone) values
  ('00000000-0000-0000-0000-000000000271','Asia/Shanghai'),
  ('00000000-0000-0000-0000-000000000272','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
  ('10000000-0000-0000-0000-000000000271','Catalog fixture','00000000-0000-0000-0000-000000000271','Asia/Shanghai','catalog-fixture'),
  ('10000000-0000-0000-0000-000000000272','Catalog trigger fixture','00000000-0000-0000-0000-000000000272','Asia/Shanghai','catalog-trigger-fixture');
insert into public.space_members(id,space_id,user_id,display_name,role) values
  ('20000000-0000-0000-0000-000000000271','10000000-0000-0000-0000-000000000271','00000000-0000-0000-0000-000000000271','Catalog owner','owner'),
  ('20000000-0000-0000-0000-000000000272','10000000-0000-0000-0000-000000000272','00000000-0000-0000-0000-000000000272','Trigger owner','owner');

-- The trusted scheduled path has no JWT principal. Its explicit source marker
-- must still run the same completion trigger as an authenticated end_focus.
do $$
declare
  enabled timestamptz;
  weekend_start date;
  start_at timestamptz;
  end_at timestamptz;
begin
  select enabled_at into enabled from private.achievement_strategy_catalog where key='weekend_warrior';
  weekend_start:=date_trunc('week',(enabled at time zone 'Asia/Shanghai')::date)::date+5;
  if weekend_start<=(enabled at time zone 'Asia/Shanghai')::date then weekend_start:=weekend_start+7; end if;
  start_at:=(weekend_start::timestamp at time zone 'Asia/Shanghai')-interval '1 minute';
  end_at:=start_at+interval '4 hours 1 minute';
  perform set_config('youjian.achievement_source','scheduled_maintenance',true);
  insert into public.focus_sessions(
    id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,
    started_at,last_seen_at,timezone_snapshot
  ) values(
    '40000000-0000-0000-0000-000000000272','10000000-0000-0000-0000-000000000272',
    '00000000-0000-0000-0000-000000000272','20000000-0000-0000-0000-000000000272',
    'Weekend boundary','work','focusing',start_at,start_at,start_at,'Asia/Shanghai'
  );
  insert into public.focus_segments(session_id,started_at,ended_at)
  values('40000000-0000-0000-0000-000000000272',start_at,end_at);
  insert into public.focus_events(session_id,actor_id,event_type,occurred_at,metadata)
  values('40000000-0000-0000-0000-000000000272','00000000-0000-0000-0000-000000000272','task_updated',
    start_at+interval '1 minute','{"old_task_name":"Weekend boundary","new_task_name":"Weekend boundary revised"}');
  update public.focus_sessions set status='completed',accumulated_focus_seconds=14460,
    active_segment_started_at=null,completed_at=end_at,completion_reason='manual_end'
  where id='40000000-0000-0000-0000-000000000272';

  insert into public.focus_sessions(
    id,space_id,user_id,member_id,task_name,category,status,active_segment_started_at,
    started_at,last_seen_at,timezone_snapshot
  ) values(
    '40000000-0000-0000-0000-000000000273','10000000-0000-0000-0000-000000000272',
    '00000000-0000-0000-0000-000000000272','20000000-0000-0000-0000-000000000272',
    'Task boundary','study','focusing',enabled+interval '10 minutes',enabled+interval '10 minutes',
    enabled+interval '10 minutes','Asia/Shanghai'
  );
  insert into public.focus_events(session_id,actor_id,event_type,occurred_at,metadata)
  values('40000000-0000-0000-0000-000000000273','00000000-0000-0000-0000-000000000272','task_updated',
    enabled+interval '11 minutes','{"old_task_name":"Task boundary","new_task_name":"Task boundary","old_category":"study","new_category":"work"}');
  insert into public.focus_events(session_id,actor_id,event_type,occurred_at,metadata)
  select '40000000-0000-0000-0000-000000000273','00000000-0000-0000-0000-000000000272','task_updated',
    enabled+make_interval(mins=>12+i),jsonb_build_object('old_task_name','Task '||i,'new_task_name','Task '||(i+1))
  from generate_series(1,3) i;
end $$;

select is(
  (select count(*)::integer from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000272' and achievement_type='weekend_warrior'),
  1,
  'scheduled settlement awards a session crossing Friday into Saturday'
);
select is(
  (select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000272' and achievement_type='task_polisher'),
  1,
  'task revision counts only actual task-name changes'
);
select is(
  (select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000272' and achievement_type='task_polisher' and metadata->>'task_revision_count'='3'),
  1,
  'third actual task-name change unlocks the polisher'
);
select is(
  (select count(*)::integer from public.personal_achievement_awards where user_id='00000000-0000-0000-0000-000000000272' and achievement_type='decisive_focus'),
  0,
  'task-name change is required before decisive focus can be considered'
);

select is(
  private.record_personal_achievement_event(
    '00000000-0000-0000-0000-000000000271','decisive_focus','10000000-0000-0000-0000-000000000271',
    null,'before-catalog',
    (select (enabled_at-interval '1 second')::date from private.achievement_strategy_catalog where key='decisive_focus'),
    (select enabled_at-interval '1 second' from private.achievement_strategy_catalog where key='decisive_focus'),
    '{"metric_value":1}'
  ),
  false,
  'catalog achievement does not backfill before activation'
);
select ok(
  private.record_personal_achievement_event(
    '00000000-0000-0000-0000-000000000271','decisive_focus','10000000-0000-0000-0000-000000000271',
    null,'decisive-first',
    (select (enabled_at+interval '1 second')::date from private.achievement_strategy_catalog where key='decisive_focus'),
    (select enabled_at+interval '1 second' from private.achievement_strategy_catalog where key='decisive_focus'),
    '{"metric_value":1}'
  ),
  'new one-time achievement records after activation'
);
select is(
  (select count from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000271' and achievement_type='decisive_focus'),
  1,
  'one-time achievement summary has one event'
);
select ok(
  not private.record_personal_achievement_event(
    '00000000-0000-0000-0000-000000000271','decisive_focus','10000000-0000-0000-0000-000000000271',
    null,'decisive-repeat','2026-08-16','2026-08-16 00:00:00+00','{"metric_value":1}'
  ),
  'one-time achievement rejects later repeats'
);
select ok(
  private.record_personal_achievement_event(
    '00000000-0000-0000-0000-000000000271','task_polisher','10000000-0000-0000-0000-000000000271',
    null,'task-third',
    (select (enabled_at+interval '2 seconds')::date from private.achievement_strategy_catalog where key='task_polisher'),
    (select enabled_at+interval '2 seconds' from private.achievement_strategy_catalog where key='task_polisher'),
    '{"task_revision_count":3}'
  ),
  'task revision threshold records at the third successful change'
);
select is(
  (select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000271' and achievement_type='task_polisher'),
  'gold',
  'task revision achievement is gold'
);

select isnt(
  private.record_shared_achievement_event(
    '10000000-0000-0000-0000-000000000271','global_timezones','global-two',
    (select enabled_at+interval '3 seconds' from private.achievement_strategy_catalog where key='global_timezones'),'silver',
    '{"timezone_count":2,"timezones":["Asia/Shanghai","Europe/Berlin"]}',
    array['20000000-0000-0000-0000-000000000271']::uuid[]
  ),
  null,
  'global series records the two-timezone stage'
);
select is(
  (select tier from public.achievements where space_id='10000000-0000-0000-0000-000000000271' and dedupe_key='global-two'),
  'silver',
  'global two-timezone event is silver'
);
select isnt(
  private.record_shared_achievement_event(
    '10000000-0000-0000-0000-000000000271','global_timezones','global-four',
    (select enabled_at+interval '4 seconds' from private.achievement_strategy_catalog where key='global_timezones'),'gold',
    '{"timezone_count":4,"timezones":["Asia/Shanghai","Europe/Berlin","America/New_York","Australia/Sydney"]}',
    array['20000000-0000-0000-0000-000000000271']::uuid[]
  ),
  null,
  'global series records the four-timezone stage'
);
select is(
  (select tier from public.achievements where space_id='10000000-0000-0000-0000-000000000271' and dedupe_key='global-four'),
  'gold',
  'global four-timezone event is gold'
);
select isnt(
  private.record_shared_achievement_event(
    '10000000-0000-0000-0000-000000000271','global_timezones','global-four-repeat',
    (select enabled_at+interval '5 seconds' from private.achievement_strategy_catalog where key='global_timezones'),'gold',
    '{"timezone_count":4}',array['20000000-0000-0000-0000-000000000271']::uuid[]
  ),
  null,
  'global series stores a post-cap repeat'
);
select is(
  (select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000271' and achievement_type='global_timezones'),
  3,
  'global series retains all three durable events'
);
select is(
  (select count(*)::integer from public.achievements where space_id='10000000-0000-0000-0000-000000000271' and achievement_type='global_timezones' and notification_eligible),
  2,
  'global series notifies only stage upgrades'
);

select ok(
  private.record_personal_achievement_event(
    '00000000-0000-0000-0000-000000000271','focus_10000_hours','10000000-0000-0000-0000-000000000271',
    null,'ten-thousand-hours',
    (select (enabled_at+interval '6 seconds')::date from private.achievement_strategy_catalog where key='focus_10000_hours'),
    (select enabled_at+interval '6 seconds' from private.achievement_strategy_catalog where key='focus_10000_hours'),
    '{"focus_minutes":600000}'
  ),
  'ten thousand hour achievement records at its exact threshold'
);
select is(
  (select tier from public.personal_achievements where user_id='00000000-0000-0000-0000-000000000271' and achievement_type='focus_10000_hours'),
  'diamond',
  'ten thousand hour achievement is diamond'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000271',true);
select is(
  public.list_personal_achievements('10000000-0000-0000-0000-000000000271',30,null)#>>'{error,code}',
  null,
  'authenticated owner can read the catalog-backed personal list'
);
select is(
  jsonb_path_query_first(
    public.list_personal_achievements('10000000-0000-0000-0000-000000000271',30,null)#>'{data,items}',
    '$[*] ? (@.achievement_type == "decisive_focus")'
  )->'read_target'->>'kind',
  'personal_tab',
  'personal response exposes the stable read target'
);

select * from finish();
rollback;
