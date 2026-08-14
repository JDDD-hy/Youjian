-- Central achievement strategy catalog.
--
-- The TypeScript JSON file is the authoring source for product metadata. This
-- private relational snapshot is the database enforcement source. Existing
-- rows are intentionally untouched; only writes at or after each strategy's
-- activation boundary use these rules.

alter table public.personal_achievement_awards
  alter column source_session_id drop not null;

create table private.achievement_strategy_catalog (
  key text primary key,
  scope text not null check (scope in ('personal','shared')),
  repeat_policy text not null check (repeat_policy in ('once','series','daily')),
  event_unit text not null check (event_unit in ('session','goal','local_day','member_count')),
  metric text not null,
  max_stage_behavior text not null,
  notification_policy text not null,
  participant_policy text not null,
  time_boundary text not null,
  legacy_aliases text[] not null default '{}'::text[],
  evaluator_id text not null,
  counter_scope text not null,
  event_key_policy text not null,
  activation_boundary text not null,
  display_policy text not null,
  read_target text not null,
  series text not null default '',
  icon text not null,
  condition text not null,
  stage_thresholds jsonb not null check (jsonb_typeof(stage_thresholds) = 'array'),
  tier_policy jsonb not null check (jsonb_typeof(tier_policy) = 'object'),
  enabled_at timestamptz not null default now()
);

insert into private.achievement_strategy_catalog(
  key,scope,repeat_policy,event_unit,metric,max_stage_behavior,
  notification_policy,participant_policy,time_boundary,evaluator_id,
  counter_scope,event_key_policy,activation_boundary,display_policy,read_target,
  series,icon,condition,legacy_aliases,stage_thresholds,tier_policy
) values
  ('night_owl','personal','once','session','count','ignore_after_unlock','first_unlock','owner','session_timezone','focus.session','user_lifetime','focus_session_id','extended_v1','attained_stage_only','personal_tab','','moon_star','本地时间 23:00—23:59 开始，跨越午夜，并累计至少 60 分钟有效专注；暂停时间不计入。','{}','[{"stage":1,"threshold":1,"stage_key":"night_owl","title":"挑灯夜战"}]','{"kind":"fixed","tier":"gold"}'),
  ('solo_focus','personal','series','session','count','cap_and_store_repeats','stage_upgrade','owner','none','focus.session','user_lifetime','focus_session_id','extended_v1','attained_stage_only','personal_tab','独行者系列','pointer','单次会话累计至少 60 分钟有效专注，且有效专注片段不与同一空间其他成员重叠。','{}','[{"stage":1,"threshold":1,"stage_key":"solo_focus","title":"孤军奋战"},{"stage":2,"threshold":5,"stage_key":"solo_focus_5","title":"独行者"},{"stage":3,"threshold":20,"stage_key":"solo_focus_20","title":"独木成林"}]','{"kind":"stage","tiers":{"1":"bronze","2":"silver","3":"gold"}}'),
  ('promise_keeper','personal','series','local_day','stage_days','cap_and_store_repeats','stage_upgrade','owner','user_local_day','focus.local_goal','user_lifetime','local_day_and_stage','extended_v1','attained_stage_only','personal_tab','守约者系列','stamp','完成当天锁定的个人专注目标，连续达成后逐级解锁。','{}','[{"stage":1,"threshold":1,"stage_key":"promise_keeper","title":"言出必行"},{"stage":2,"threshold":3,"stage_key":"promise_keeper_3","title":"初守约定"},{"stage":3,"threshold":7,"stage_key":"promise_keeper_7","title":"滴水穿石"},{"stage":4,"threshold":30,"stage_key":"promise_keeper_30","title":"久久为功"}]','{"kind":"stage","tiers":{"1":"bronze","2":"silver","3":"gold","4":"diamond"}}'),
  ('dawn_walker','personal','once','session','count','ignore_after_unlock','first_unlock','owner','session_timezone','focus.session','user_lifetime','focus_session_id','extended_v1','attained_stage_only','personal_tab','','sunrise','本地时间 05:00—06:59 开始，并累计至少 60 分钟有效专注。','{}','[{"stage":1,"threshold":1,"stage_key":"dawn_walker","title":"破晓而行"}]','{"kind":"fixed","tier":"gold"}'),
  ('unbroken_focus','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.session','user_lifetime','focus_session_id','extended_v1','attained_stage_only','personal_tab','','move_right','整个会话从未暂停，并连续完成至少 60 分钟有效专注。','{}','[{"stage":1,"threshold":1,"stage_key":"unbroken_focus","title":"一气呵成"}]','{"kind":"fixed","tier":"gold"}'),
  ('double_focus','personal','once','local_day','count','ignore_after_unlock','first_unlock','owner','user_local_day','focus.local_day','user_lifetime','local_day','extended_v1','attained_stage_only','personal_tab','','spline','同一本地自然日完成 2 次专注，每次至少 30 分钟，且均未跨日。','{}','[{"stage":1,"threshold":1,"stage_key":"double_focus","title":"梅开二度"}]','{"kind":"fixed","tier":"gold"}'),
  ('triple_focus','personal','once','local_day','count','ignore_after_unlock','first_unlock','owner','user_local_day','focus.local_day','user_lifetime','local_day','extended_v1','attained_stage_only','personal_tab','','ev_charger','同一本地自然日完成 3 次专注，每次至少 30 分钟，且均未跨日。','{}','[{"stage":1,"threshold":1,"stage_key":"triple_focus","title":"三顾书桌"}]','{"kind":"fixed","tier":"gold"}'),
  ('three_categories','personal','once','local_day','count','ignore_after_unlock','first_unlock','owner','user_local_day','focus.local_day','user_lifetime','local_day','extended_v1','attained_stage_only','personal_tab','','hexagon','同一本地自然日在 3 个不同最终任务类别中分别累计至少 30 分钟。','{}','[{"stage":1,"threshold":1,"stage_key":"three_categories","title":"六边形战士"}]','{"kind":"fixed","tier":"gold"}'),
  ('return_after_break','personal','once','local_day','count','ignore_after_unlock','first_unlock','owner','user_local_day','focus.local_day','user_lifetime','local_day','extended_v1','attained_stage_only','personal_tab','','list_restart','连续 7 个完整本地自然日没有有效专注后，回归当天累计至少 60 分钟。','{}','[{"stage":1,"threshold":1,"stage_key":"return_after_break","title":"久别重逢"}]','{"kind":"fixed","tier":"gold"}'),
  ('together_streak','shared','series','local_day','days','cap_and_store_repeats','stage_upgrade','qualifying_members','space_local_day','shared.local_day','space_lifetime','space_day','extended_v1','attained_stage_only','shared_card','相伴系列','lamp_desk','空间内至少两名有效成员全部完成空间签到目标，连续达成后逐级解锁。',ARRAY['three_days_together','three_day_together','together_lit'],'[{"stage":1,"threshold":1,"stage_key":"together_streak_1","title":"1 日相伴"},{"stage":2,"threshold":3,"stage_key":"together_streak_3","title":"3 日相伴"},{"stage":3,"threshold":7,"stage_key":"together_streak_7","title":"7 日相伴"}]','{"kind":"stage","tiers":{"1":"bronze","2":"silver","3":"gold"}}'),
  ('goal_milestone','shared','series','goal','completed_goal_count','cap_and_store_repeats','stage_upgrade','goal_participants','none','shared.goal_completion','space_lifetime','goal_id','extended_v1','attained_stage_only','shared_card','共同目标系列','target','空间累计完成经成员投票通过的共同目标。',ARRAY['first_goal'],'[{"stage":1,"threshold":1,"stage_key":"goal_milestone_1","title":"完成 1 个共同目标"},{"stage":2,"threshold":3,"stage_key":"goal_milestone_3","title":"完成 3 个共同目标"},{"stage":3,"threshold":10,"stage_key":"goal_milestone_10","title":"完成 10 个共同目标"}]','{"kind":"stage","tiers":{"1":"bronze","2":"silver","3":"gold"}}'),
  ('focus_milestone','shared','series','session','threshold_minutes','cap_and_store_repeats','stage_upgrade','qualifying_members','none','shared.focus_total','space_lifetime','focus_session_id','extended_v1','attained_stage_only','shared_card','时光里程碑','metronome','空间累计有效专注达到对应小时数。','{}','[{"stage":1,"threshold":600,"stage_key":"focus_milestone_600","title":"累计专注 10 小时"},{"stage":2,"threshold":3000,"stage_key":"focus_milestone_3000","title":"累计专注 50 小时"},{"stage":3,"threshold":6000,"stage_key":"focus_milestone_6000","title":"累计专注 100 小时"}]','{"kind":"stage","tiers":{"1":"bronze","2":"silver","3":"gold"}}'),
  ('chance_encounter','shared','once','session','count','ignore_after_unlock','first_unlock','qualifying_members','space_local_day','shared.focus_overlap','space_lifetime','overlap_window','extended_v1','attained_stage_only','shared_card','','orbit','成员开始时间相邻不超过 3 分钟，并共同连续专注至少 30 分钟。','{}','[{"stage":1,"threshold":1,"stage_key":"chance_encounter","title":"不期而遇"}]','{"kind":"fixed","tier":"gold"}'),
  ('fellow_travelers','shared','series','member_count','member_count','cap_and_store_repeats','stage_upgrade','qualifying_members','space_local_day','shared.focus_overlap','space_lifetime','overlap_window','extended_v1','attained_stage_only','shared_card','同行者系列','shapes','至少 3 名成员连续共同专注 30 分钟。','{}','[{"stage":1,"threshold":3,"stage_key":"fellow_travelers_3","title":"三人成行"},{"stage":2,"threshold":5,"stage_key":"fellow_travelers_5","title":"万家灯火"}]','{"kind":"stage","tiers":{"1":"silver","2":"gold"}}'),
  ('focus_relay','shared','once','session','count','ignore_after_unlock','first_unlock','qualifying_members','space_local_day','shared.focus_relay','space_lifetime','relay_pair_and_day','extended_v1','attained_stage_only','shared_card','','heart_handshake','一名成员完成至少 30 分钟后，另一名成员在 5 分钟内开始并完成至少 30 分钟。','{}','[{"stage":1,"threshold":1,"stage_key":"focus_relay","title":"接力燃灯"}]','{"kind":"fixed","tier":"gold"}'),
  ('living_flame','shared','daily','local_day','qualified_member_count','one_per_local_day','first_unlock','qualifying_members','space_local_day','shared.full_day_union','space_local_day','space_day','extended_v1','attained_stage_only','shared_card','','flame_kindling','按空间时区计算：至少两名成员各有效专注 30 分钟，且其有效专注片段并集完整覆盖本地自然日。','{}','[{"stage":1,"threshold":2,"stage_key":"living_flame","title":"星火相传"}]','{"kind":"fixed","tier":"gold"}'),
  ('global_timezones','shared','series','session','timezone_count','cap_and_store_repeats','stage_upgrade','qualifying_members','session_timezone','shared.focus_timezone_overlap','space_lifetime','focus_session_id','catalog_v1','attained_stage_only','shared_card','全球系列','globe','同一共享专注事件中，同时有效专注成员来自至少对应数量的不同 IANA 时区。','{}','[{"stage":1,"threshold":2,"stage_key":"global_timezones_2","title":"天涯共此时"},{"stage":2,"threshold":4,"stage_key":"global_timezones_4","title":"五湖四海"}]','{"kind":"stage","tiers":{"1":"bronze","2":"silver"}}'),
  ('task_polisher','personal','once','session','task_revision_count','ignore_after_unlock','first_unlock','owner','none','focus.task_revision','focus_session','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','hammer','同一个任务成功修改名称至少 3 次；无变化提交不计入。','{}','[{"stage":1,"threshold":3,"stage_key":"task_polisher","title":"精雕细琢"}]','{"kind":"fixed","tier":"gold"}'),
  ('decisive_focus','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.session_no_task_revision','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','anvil','单次专注从开始到完成没有修改过任务名称，且有效专注时长至少 60 分钟；暂停允许。','{}','[{"stage":1,"threshold":1,"stage_key":"decisive_focus","title":"一锤定音"}]','{"kind":"fixed","tier":"gold"}'),
  ('restless_focus','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.short_session','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','metronome','累计 3 次有效专注时长大于 0 且少于 5 分钟的 session。','{}','[{"stage":1,"threshold":3,"stage_key":"restless_focus","title":"如坐针毡"}]','{"kind":"fixed","tier":"gold"}'),
  ('work_diligence','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.category_session','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','briefcase','完成 10 次最终类型为“工作”的有效专注 session。','{}','[{"stage":1,"threshold":10,"stage_key":"work_diligence","title":"兢兢业业"}]','{"kind":"fixed","tier":"gold"}'),
  ('learning_seeker','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.category_session','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','book_open','完成 10 次最终类型为“学习”的有效专注 session。','{}','[{"stage":1,"threshold":10,"stage_key":"learning_seeker","title":"学海无涯"}]','{"kind":"fixed","tier":"gold"}'),
  ('bookworm','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.category_session','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','book_marked','完成 10 次最终类型为“阅读”的有效专注 session。','{}','[{"stage":1,"threshold":10,"stage_key":"bookworm","title":"书虫"}]','{"kind":"fixed","tier":"gold"}'),
  ('mystery_work','personal','once','session','count','ignore_after_unlock','first_unlock','owner','none','focus.category_session','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','sparkles','完成 10 次最终类型为“其他”的有效专注 session。','{}','[{"stage":1,"threshold":10,"stage_key":"mystery_work","title":"神秘事务"}]','{"kind":"fixed","tier":"gold"}'),
  ('weekend_warrior','personal','once','local_day','weekend_focus_minutes','ignore_after_unlock','first_unlock','owner','user_local_weekend','focus.weekend_window','user_lifetime','local_weekend','catalog_v1','attained_stage_only','personal_tab','','trees','在一个用户本地周末（周六 00:00 至周一 00:00）累计至少 240 分钟有效专注。','{}','[{"stage":1,"threshold":240,"stage_key":"weekend_warrior","title":"周末战士"}]','{"kind":"fixed","tier":"gold"}'),
  ('focus_10000_hours','personal','once','session','focus_minutes','ignore_after_unlock','first_unlock','owner','none','focus.lifetime_total','user_lifetime','focus_session_id','catalog_v1','attained_stage_only','personal_tab','','gem','个人累计有效专注达到 10,000 小时（600,000 分钟）。','{}','[{"stage":1,"threshold":600000,"stage_key":"focus_10000_hours","title":"万时户"}]','{"kind":"fixed","tier":"diamond"}'),
  ('first_invitee','personal','once','member_count','count','ignore_after_unlock','first_unlock','space_owner','none','membership.first_new_member','space_lifetime','membership_id','catalog_v1','attained_stage_only','personal_tab','','person_standing','你邀请的第一位新成员成功加入友间。','{}','[{"stage":1,"threshold":1,"stage_key":"first_invitee","title":"虚左以待"}]','{"kind":"fixed","tier":"gold"}'),
  ('full_house','personal','once','member_count','member_count','ignore_after_unlock','first_unlock','space_owner','none','membership.capacity_reached','space_lifetime','space_capacity_reached','catalog_v1','attained_stage_only','personal_tab','','building','友间第一次达到成员上限，且当前成员至少 5 人。','{}','[{"stage":1,"threshold":5,"stage_key":"full_house","title":"高朋满座"}]','{"kind":"fixed","tier":"gold"}');

update private.achievement_strategy_catalog
set enabled_at = private.extended_achievements_enabled_at()
where activation_boundary = 'extended_v1';

-- Final visual selections for the newly-added strategies. Existing strategy
-- icons remain unchanged; these updates only apply to this new batch.
update private.achievement_strategy_catalog
set icon=case key
  when 'global_timezones' then 'plane'
  when 'task_polisher' then 'wand_sparkles'
  when 'decisive_focus' then 'gavel'
  when 'restless_focus' then 'circle_fading_arrow_up'
  when 'work_diligence' then 'briefcase_business'
  when 'learning_seeker' then 'notebook_pen'
  when 'bookworm' then 'worm'
  when 'mystery_work' then 'badge_question_mark'
  when 'weekend_warrior' then 'award'
  when 'focus_10000_hours' then 'wine'
  when 'first_invitee' then 'sofa'
  when 'full_house' then 'smile_plus'
  else icon
end
where key in(
  'global_timezones','task_polisher','decisive_focus','restless_focus',
  'work_diligence','learning_seeker','bookworm','mystery_work',
  'weekend_warrior','focus_10000_hours','first_invitee','full_house'
);

update private.achievement_strategy_catalog
set stage_thresholds='[{"stage":1,"threshold":2,"stage_key":"global_timezones_2","title":"天涯共此时","icon":"plane"},{"stage":2,"threshold":4,"stage_key":"global_timezones_4","title":"五湖四海","icon":"earth"}]'::jsonb,
    tier_policy='{"kind":"stage","tiers":{"1":"silver","2":"gold"}}'::jsonb
where key='global_timezones';

update private.achievement_strategy_catalog
set condition='按空间时区计算：至少两名合格成员，每名合格成员累计有效专注至少 30 分钟，且其有效专注片段并集完整覆盖当天 00:00 连续覆盖至次日 00:00；重叠部分只计算一次。'
where key='living_flame';

-- Scheduled settlement runs as postgres without an auth principal. Mark that
-- trusted server path explicitly so the same triggers remain isolated from
-- raw SQL fixtures while still evaluating automatic completions.
create or replace function private.run_scheduled_minute_maintenance() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform set_config('youjian.achievement_source','scheduled_maintenance',true);
  return private.run_minute_maintenance_as('cron');
end $$;

create or replace function public.current_user_is_active_member(p_space_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.space_members m
    where m.space_id=p_space_id
      and m.user_id=private.current_principal_id()
      and m.status='active')
$$;

create or replace function public.current_user_is_owner(p_space_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.space_members m
    where m.space_id=p_space_id and m.user_id=private.current_principal_id()
      and m.role='owner' and m.status='active')
$$;

create index achievement_strategy_catalog_aliases
  on private.achievement_strategy_catalog using gin (legacy_aliases);

create or replace function private.canonical_achievement_type(p_type text)
returns text language sql stable security definer set search_path='' as $$
  select coalesce(
    (select c.key from private.achievement_strategy_catalog c
      where p_type = c.key or p_type = any(c.legacy_aliases) limit 1),
    p_type
  )
$$;

create or replace function private.achievement_strategy_enabled_at(p_type text)
returns timestamptz language sql stable security definer set search_path='' as $$
  select case when activation_boundary='extended_v1' then private.extended_achievements_enabled_at()
    else enabled_at end
  from private.achievement_strategy_catalog
  where key=private.canonical_achievement_type(p_type)
$$;

create or replace function private.achievement_stage(
  p_type text,p_count integer,p_metadata jsonb
) returns integer
language plpgsql stable security definer set search_path='' as $$
declare
  strategy private.achievement_strategy_catalog%rowtype;
  metric_value numeric;
  result integer;
begin
  select * into strategy from private.achievement_strategy_catalog
    where key=private.canonical_achievement_type(p_type);
  if not found then return 0; end if;
  metric_value:=case when strategy.metric='count'
    then coalesce((coalesce(p_metadata,'{}'::jsonb)->>'metric_value')::numeric,coalesce(p_count,0))
    else coalesce((coalesce(p_metadata,'{}'::jsonb)->>strategy.metric)::numeric,0) end;
  select coalesce(max((stage->>'stage')::integer),0) into result
  from jsonb_array_elements(strategy.stage_thresholds) stage
  where metric_value >= (stage->>'threshold')::numeric;
  return result;
exception when invalid_text_representation or numeric_value_out_of_range then
  return 0;
end $$;

create or replace function private.achievement_tier(p_type text,p_stage integer)
returns text language plpgsql stable security definer set search_path='' as $$
declare policy jsonb; result text;
begin
  select tier_policy into policy from private.achievement_strategy_catalog
    where key=private.canonical_achievement_type(p_type);
  if policy is null then return 'bronze'; end if;
  if policy->>'kind'='fixed' then return policy->>'tier'; end if;
  select value into result from jsonb_each_text(policy->'tiers')
    where key::integer<=coalesce(p_stage,0)
    order by key::integer desc limit 1;
  return coalesce(result,'bronze');
end $$;

create or replace function private.personal_tier(p_type text,p_count integer,p_metadata jsonb)
returns text language sql stable security definer set search_path='' as $$
  select private.achievement_tier(p_type,private.achievement_stage(p_type,p_count,p_metadata))
$$;

create or replace function private.record_personal_achievement_event(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_event_key text,
  p_local_date date,p_earned_at timestamptz,p_metadata jsonb default '{}'::jsonb
) returns boolean
language plpgsql security definer set search_path='' as $$
declare
  canonical text:=private.canonical_achievement_type(p_type);
  strategy private.achievement_strategy_catalog%rowtype;
  inserted_id uuid;
  prior_count integer:=0;
  prior_stage integer:=0;
  next_count integer;
  next_stage integer;
  notify boolean:=false;
  prior_metadata jsonb:='{}'::jsonb;
  merged_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  metric_name text;
  prior_metric numeric;
  next_metric numeric;
  event_date date:=p_local_date;
begin
  select * into strategy from private.achievement_strategy_catalog where key=canonical;
  if not found or strategy.scope<>'personal' then
    raise exception using errcode='22023',message='invalid personal achievement type';
  end if;
  if p_event_key is null or p_earned_at is null or p_space_id is null then
    raise exception using errcode='22023',message='achievement event identity is required';
  end if;
  if strategy.activation_boundary='catalog_v1'
    and p_earned_at < private.achievement_strategy_enabled_at(canonical) then return false; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text||':'||canonical,140601)
  );

  select pa.count,pa.metadata
    into prior_count,prior_metadata
  from public.personal_achievements pa
  where pa.user_id=p_user_id and pa.achievement_type=canonical
  for update;
  prior_count:=coalesce(prior_count,0);
  prior_metadata:=coalesce(prior_metadata,'{}'::jsonb);
  prior_stage:=private.achievement_stage(canonical,prior_count,prior_metadata);

  if strategy.repeat_policy='once' and (
    exists(select 1 from public.personal_achievement_awards e
      where e.user_id=p_user_id and private.canonical_achievement_type(e.achievement_type)=canonical)
    or prior_count>0
  ) then return false; end if;

  merged_metadata:=prior_metadata||coalesce(p_metadata,'{}'::jsonb);
  metric_name:=strategy.metric;
  if metric_name<>'count' then
    prior_metric:=coalesce((prior_metadata->>metric_name)::numeric,0);
    next_metric:=greatest(prior_metric,coalesce((p_metadata->>metric_name)::numeric,0));
    if next_metric>0 then
      merged_metadata:=jsonb_set(merged_metadata,ARRAY[metric_name],to_jsonb(next_metric),true);
    end if;
  end if;
  if canonical='promise_keeper' then
    merged_metadata:=jsonb_set(merged_metadata,'{stage_days}',to_jsonb(greatest(
      coalesce((prior_metadata->>'stage_days')::integer,0),
      coalesce((p_metadata->>'stage_days')::integer,0)
    )),true);
  end if;
  next_count:=prior_count+1;
  next_stage:=private.achievement_stage(canonical,next_count,merged_metadata);
  if next_stage=0 then return false; end if;

  if event_date is null then
    select (p_earned_at at time zone coalesce(pr.timezone,'UTC'))::date into event_date
    from public.profiles pr where pr.id=p_user_id;
  end if;
  notify:=case strategy.repeat_policy
    when 'once' then true
    when 'series' then next_stage>prior_stage
    when 'daily' then not exists(
      select 1 from public.personal_achievement_awards e
      where e.user_id=p_user_id and private.canonical_achievement_type(e.achievement_type)=canonical
        and e.notification_eligible and e.local_date=event_date)
    else false end;

  insert into public.personal_achievement_awards(
    user_id,achievement_type,source_space_id,source_session_id,event_key,
    local_date,earned_at,metadata,notification_eligible
  ) values(
    p_user_id,canonical,p_space_id,p_session_id,p_event_key,event_date,p_earned_at,
    coalesce(p_metadata,'{}'::jsonb),notify
  ) on conflict(user_id,achievement_type,event_key) do nothing returning id into inserted_id;
  if inserted_id is null then return false; end if;

  insert into public.personal_achievements(
    user_id,achievement_type,first_earned_at,last_earned_at,last_unlocked_at,
    count,tier,metadata
  ) values(
    p_user_id,canonical,p_earned_at,p_earned_at,
    case when notify then p_earned_at else p_earned_at end,
    1,private.personal_tier(canonical,1,merged_metadata),merged_metadata
  ) on conflict(user_id,achievement_type) do update set
    first_earned_at=least(public.personal_achievements.first_earned_at,excluded.first_earned_at),
    last_earned_at=greatest(public.personal_achievements.last_earned_at,excluded.last_earned_at),
    last_unlocked_at=case when notify then greatest(public.personal_achievements.last_unlocked_at,excluded.last_unlocked_at)
      else public.personal_achievements.last_unlocked_at end,
    count=public.personal_achievements.count+1,
    tier=private.personal_tier(canonical,public.personal_achievements.count+1,merged_metadata),
    metadata=merged_metadata;
  return true;
end $$;

create or replace function private.record_personal_achievement(
  p_user_id uuid,p_type text,p_space_id uuid,p_session_id uuid,p_earned_at timestamptz
) returns boolean
language sql security definer set search_path='' as $$
  select private.record_personal_achievement_event(
    p_user_id,p_type,p_space_id,p_session_id,p_session_id::text,
    (p_earned_at at time zone 'UTC')::date,p_earned_at,'{}'::jsonb
  )
$$;

create or replace function private.shared_achievement_tier(p_type text,p_stage integer)
returns text language sql stable security definer set search_path='' as $$
  select private.achievement_tier(p_type,p_stage)
$$;

create or replace function private.record_shared_achievement_event(
  p_space_id uuid,p_type text,p_key text,p_at timestamptz,p_tier text,p_metadata jsonb,p_members uuid[]
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  canonical text:=private.canonical_achievement_type(p_type);
  strategy private.achievement_strategy_catalog%rowtype;
  aid uuid;
  mid uuid;
  prior_stage integer:=0;
  next_stage integer:=0;
  notify boolean:=false;
  metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  local_date date;
begin
  select * into strategy from private.achievement_strategy_catalog where key=canonical;
  if not found or strategy.scope<>'shared' then
    raise exception using errcode='22023',message='invalid shared achievement type';
  end if;
  if p_key is null or p_at is null or p_space_id is null then
    raise exception using errcode='22023',message='achievement event identity is required';
  end if;
  -- Keep the legacy function signature stable; catalog tiers are authoritative.
  perform p_tier;
  if strategy.activation_boundary='catalog_v1'
    and p_at < private.achievement_strategy_enabled_at(canonical) then return null; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_space_id::text||':'||canonical,140602)
  );

  -- Threshold facts that are safely reconstructible from durable rows are
  -- re-read after the lock. This is the serialization boundary for stages.
  if canonical='goal_milestone' then
    select count(*)::integer into next_stage from public.goals
      where space_id=p_space_id and status='completed';
    metadata:=metadata||jsonb_build_object('completed_goal_count',next_stage);
  elsif canonical='focus_milestone' then
    select floor(coalesce(sum(accumulated_focus_seconds),0)/60.0)::integer into next_stage
    from public.focus_sessions where space_id=p_space_id and status='completed';
    metadata:=metadata||jsonb_build_object('threshold_minutes',next_stage);
  end if;

  select coalesce(max(private.achievement_stage(a.achievement_type,1,a.metadata)),0)
    into prior_stage
  from public.achievements a
  where a.space_id=p_space_id and private.canonical_achievement_type(a.achievement_type)=canonical;
  next_stage:=private.achievement_stage(canonical,1,metadata);

  if strategy.repeat_policy='once' and exists(
    select 1 from public.achievements a
    where a.space_id=p_space_id and private.canonical_achievement_type(a.achievement_type)=canonical
  ) then return null; end if;
  if strategy.repeat_policy='series' then
    notify:=next_stage>prior_stage;
  elsif strategy.repeat_policy='daily' then
    select coalesce((metadata->>'local_date')::date,(p_at at time zone s.timezone)::date)
      into local_date from public.spaces s where s.id=p_space_id;
    metadata:=jsonb_set(metadata,'{local_date}',to_jsonb(local_date),true);
    notify:=case when strategy.notification_policy='first_unlock' then not exists(
      select 1 from public.achievements a
      where a.space_id=p_space_id
        and private.canonical_achievement_type(a.achievement_type)=canonical
        and a.notification_eligible
    ) else not exists(
      select 1 from public.achievements a
      where a.space_id=p_space_id and private.canonical_achievement_type(a.achievement_type)=canonical
        and a.notification_eligible
        and coalesce((a.metadata->>'local_date')::date,(a.earned_at at time zone (select timezone from public.spaces where id=p_space_id))::date)=local_date
    ) end;
  else
    notify:=true;
  end if;
  -- focus_milestone historically stores below-threshold settlement facts so
  -- the shared read RPC can filter them without rewriting history.
  if next_stage=0 and canonical<>'focus_milestone' then return null; end if;

  insert into public.achievements(
    space_id,achievement_type,dedupe_key,earned_at,metadata,tier,
    participants_recorded,notification_eligible
  ) values(
    p_space_id,canonical,p_key,p_at,metadata,private.achievement_tier(canonical,next_stage),
    true,notify
  ) on conflict(space_id,dedupe_key) do nothing returning id into aid;
  if aid is null then return null; end if;

  foreach mid in array coalesce(p_members,'{}'::uuid[]) loop
    insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot)
    select aid,id,display_name from public.space_members where id=mid
    on conflict do nothing;
  end loop;
  return aid;
end $$;

create or replace function private.guard_legacy_achievement_inserts() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  -- Compatibility facts remain queryable, but never become new notifications.
  if (new.achievement_type='first_goal' and new.dedupe_key like 'first-goal%')
    or (new.achievement_type='three_days_together' and new.dedupe_key like 'three-days:%')
    or (new.achievement_type='three_day_together' and new.dedupe_key like 'three-days:%')
    or new.achievement_type='together_lit' then
    new.notification_eligible:=false;
    return new;
  end if;
  if (new.achievement_type='focus_milestone' and new.dedupe_key like 'milestone:%')
    or (new.achievement_type='goal_milestone' and new.dedupe_key like 'goal-count:%')
    or (new.achievement_type='together_streak' and new.dedupe_key in('together-streak:1','together-streak:3','together-streak:7')) then
    return null;
  end if;
  return new;
end $$;

create or replace function private.evaluate_catalog_personal_focus_achievements() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  seconds integer;
  short_count integer;
  category_count integer;
  weekend_minutes integer;
  lifetime_minutes integer;
  local_day date;
  weekend_start date;
  weekend_end timestamptz;
  weekend_day date;
  local_start timestamp;
  category_type text;
  task_revised boolean;
  p_at timestamptz:=coalesce(new.completed_at,now());
begin
  if private.current_principal_id() is null
    and coalesce(current_setting('youjian.achievement_source',true),'')<>'scheduled_maintenance' then return new; end if;
  if new.status not in('completed','discarded') or old.status in('completed','discarded') then return new; end if;
  select coalesce(sum(extract(epoch from (g.ended_at-g.started_at))),0)::integer
    into seconds
  from public.focus_segments g where g.session_id=new.id and g.ended_at is not null;
  local_start:=new.started_at at time zone new.timezone_snapshot;
  local_day:=local_start::date;

  -- A discarded 0-to-5-minute session is still a real short-focus event. It
  -- does not count toward stats or any completed-session achievement.
  if seconds>0 and seconds<300 and new.started_at>=private.achievement_strategy_enabled_at('restless_focus') then
    select count(*)::integer into short_count
    from public.focus_sessions s
    where s.user_id=new.user_id and s.started_at>=private.achievement_strategy_enabled_at('restless_focus')
      and s.status in('completed','discarded') and s.accumulated_focus_seconds>0
      and s.accumulated_focus_seconds<300;
    perform private.record_personal_achievement_event(
      new.user_id,'restless_focus',new.space_id,new.id,new.id::text,local_day,p_at,
      jsonb_build_object('metric_value',short_count,'effective_seconds',seconds)
    );
  end if;

  if new.status<>'completed' then return new; end if;

  select exists(select 1 from public.focus_events e
    where e.session_id=new.id and e.event_type='task_updated'
      and (e.metadata->>'old_task_name') is distinct from (e.metadata->>'new_task_name')) into task_revised;
  if seconds>=3600 and not task_revised
    and new.started_at>=private.achievement_strategy_enabled_at('decisive_focus') then
    perform private.record_personal_achievement_event(
      new.user_id,'decisive_focus',new.space_id,new.id,new.id::text,local_day,p_at,
      jsonb_build_object('metric_value',1,'effective_seconds',seconds)
    );
  end if;

  category_type:=case new.category::text
    when 'work' then 'work_diligence'
    when 'study' then 'learning_seeker'
    when 'reading' then 'bookworm'
    when 'other' then 'mystery_work'
    else null end;
  if category_type is not null and seconds>0
    and new.started_at>=private.achievement_strategy_enabled_at(category_type) then
    select count(*)::integer into category_count
    from public.focus_sessions s
    where s.user_id=new.user_id and s.category=new.category and s.status='completed'
      and s.started_at>=private.achievement_strategy_enabled_at(category_type)
      and s.accumulated_focus_seconds>0;
    perform private.record_personal_achievement_event(
      new.user_id,category_type,new.space_id,new.id,new.id::text,local_day,p_at,
      jsonb_build_object('metric_value',category_count,'category',new.category::text)
    );
  end if;

  if new.started_at>=private.achievement_strategy_enabled_at('weekend_warrior') then
    -- Anchor the weekend to completion time so a Friday session that crosses
    -- midnight contributes its Saturday segment to the current weekend.
    weekend_day:=(p_at at time zone new.timezone_snapshot)::date;
    weekend_start:=weekend_day-((extract(dow from weekend_day)::integer+1)%7);
    weekend_end:=(weekend_start+2)::timestamp at time zone new.timezone_snapshot;
    select floor(coalesce(sum(extract(epoch from(
      least(g.ended_at,weekend_end)-greatest(g.started_at,weekend_start::timestamp at time zone new.timezone_snapshot)
    ))),0)/60.0)::integer into weekend_minutes
    from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
    where s.user_id=new.user_id and s.status='completed'
      and s.started_at>=private.achievement_strategy_enabled_at('weekend_warrior')
      and g.ended_at is not null
      and g.started_at<weekend_end
      and g.ended_at>(weekend_start::timestamp at time zone new.timezone_snapshot);
    perform private.record_personal_achievement_event(
      new.user_id,'weekend_warrior',new.space_id,new.id,'weekend:'||weekend_start::text,local_day,p_at,
      jsonb_build_object('weekend_focus_minutes',weekend_minutes,'weekend_start',weekend_start::text)
    );
  end if;

  if new.started_at>=private.achievement_strategy_enabled_at('focus_10000_hours') then
    select floor(coalesce(sum(extract(epoch from(g.ended_at-g.started_at))),0)/60.0)::integer
      into lifetime_minutes
    from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
    where s.user_id=new.user_id and s.status='completed'
      and s.started_at>=private.achievement_strategy_enabled_at('focus_10000_hours')
      and g.ended_at is not null;
    perform private.record_personal_achievement_event(
      new.user_id,'focus_10000_hours',new.space_id,new.id,new.id::text,local_day,p_at,
      jsonb_build_object('focus_minutes',lifetime_minutes)
    );
  end if;
  return new;
end $$;

drop trigger if exists focus_sessions_catalog_personal_achievements on public.focus_sessions;
create trigger focus_sessions_catalog_personal_achievements
after update of status on public.focus_sessions
for each row when(old.status in('focusing','paused') and new.status in('completed','discarded'))
execute function private.evaluate_catalog_personal_focus_achievements();

create or replace function private.evaluate_catalog_task_revision_achievement() returns trigger
language plpgsql security definer set search_path='' as $$
declare s public.focus_sessions%rowtype; revision_count integer;
begin
  if private.current_principal_id() is null
    and coalesce(current_setting('youjian.achievement_source',true),'')<>'scheduled_maintenance' then return new; end if;
  if new.event_type<>'task_updated' then return new; end if;
  select * into s from public.focus_sessions where id=new.session_id;
  if not found or s.user_id<>new.actor_id or s.status not in('focusing','paused') then return new; end if;
  if s.started_at<private.achievement_strategy_enabled_at('task_polisher') then return new; end if;
  select count(*)::integer into revision_count from public.focus_events e
    where e.session_id=new.session_id and e.event_type='task_updated'
      and (e.metadata->>'old_task_name') is distinct from (e.metadata->>'new_task_name');
  if revision_count=0 then return new; end if;
  perform private.record_personal_achievement_event(
    s.user_id,'task_polisher',s.space_id,s.id,s.id::text,
    (s.started_at at time zone s.timezone_snapshot)::date,new.occurred_at,
    jsonb_build_object('task_revision_count',revision_count)
  );
  return new;
end $$;

drop trigger if exists focus_events_catalog_task_revision on public.focus_events;
create trigger focus_events_catalog_task_revision
after insert on public.focus_events for each row
execute function private.evaluate_catalog_task_revision_achievement();

create or replace function private.evaluate_catalog_global_timezones() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  members uuid[];
  timezones text[];
  timezone_count integer;
begin
  if private.current_principal_id() is null
    and coalesce(current_setting('youjian.achievement_source',true),'')<>'scheduled_maintenance' then return new; end if;
  if new.status<>'completed' or old.status in('completed','discarded') then return new; end if;
  if new.started_at<private.achievement_strategy_enabled_at('global_timezones') then return new; end if;

  -- Serialize before taking the cross-member snapshot. A concurrent session
  -- completing on the same space/type is therefore visible to the next
  -- evaluator before it decides whether a new stage was reached.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.space_id::text||':global_timezones',140602)
  );
  with current_session as(
    select new.member_id member_id,new.timezone_snapshot timezone_snapshot,g.started_at,g.ended_at
    from public.focus_segments g where g.session_id=new.id and g.ended_at is not null
  ), overlapping as(
    select distinct s.member_id,s.timezone_snapshot
    from public.focus_sessions s join public.focus_segments g on g.session_id=s.id
    where s.space_id=new.space_id and s.status='completed'
      and s.started_at>=private.achievement_strategy_enabled_at('global_timezones')
      and g.ended_at is not null and exists(
        select 1 from current_session c
        where g.started_at<c.ended_at and g.ended_at>c.started_at
      )
  )
  select array_agg(distinct member_id order by member_id),array_agg(distinct timezone_snapshot order by timezone_snapshot),count(distinct timezone_snapshot)::integer
    into members,timezones,timezone_count from overlapping;
  if timezone_count>=2 then
    perform private.record_shared_achievement_event(
      new.space_id,'global_timezones','global-timezones:'||new.id::text,
      coalesce(new.completed_at,now()),'bronze',
      jsonb_build_object('timezone_count',timezone_count,'timezones',timezones),members
    );
  end if;
  return new;
end $$;

drop trigger if exists focus_sessions_catalog_global_timezones on public.focus_sessions;
create trigger focus_sessions_catalog_global_timezones
after update of status on public.focus_sessions
for each row when(old.status in('focusing','paused') and new.status='completed')
execute function private.evaluate_catalog_global_timezones();

create or replace function private.evaluate_catalog_membership_achievements() returns trigger
language plpgsql security definer set search_path='' as $$
declare
  space_row public.spaces%rowtype;
  active_count integer;
  owner_tz text;
begin
  if private.current_principal_id() is null
    and coalesce(current_setting('youjian.achievement_source',true),'')<>'scheduled_maintenance' then return new; end if;
  select * into space_row from public.spaces where id=new.space_id;
  if not found then return new; end if;
  select count(*)::integer into active_count from public.space_members
    where space_id=new.space_id and status='active';

  if TG_OP='INSERT' and new.role='member'
    and new.joined_at>=private.achievement_strategy_enabled_at('first_invitee') then
    select p.timezone into owner_tz from public.profiles p where p.id=space_row.owner_id;
    perform private.record_personal_achievement_event(
      space_row.owner_id,'first_invitee',new.space_id,null,new.id::text,
      (new.joined_at at time zone coalesce(owner_tz,space_row.timezone))::date,new.joined_at,
      jsonb_build_object('membership_id',new.id::text,'member_count',active_count)
    );
  end if;

  if active_count>=5 and active_count>=space_row.member_limit
    and now()>=private.achievement_strategy_enabled_at('full_house') then
    perform private.record_personal_achievement_event(
      space_row.owner_id,'full_house',new.space_id,null,
      'capacity:'||new.space_id::text||':'||space_row.member_limit::text,
      (new.joined_at at time zone coalesce(owner_tz,space_row.timezone))::date,
      greatest(new.joined_at,now()),
      jsonb_build_object('member_count',active_count,'member_limit',space_row.member_limit)
    );
  end if;
  return new;
end $$;

drop trigger if exists space_members_catalog_achievements on public.space_members;
create trigger space_members_catalog_achievements
after insert or update of status on public.space_members
for each row when(new.status='active')
execute function private.evaluate_catalog_membership_achievements();

create or replace function private.evaluate_catalog_capacity_achievement() returns trigger
language plpgsql security definer set search_path='' as $$
declare active_count integer; owner_tz text; at_time timestamptz:=now();
begin
  if private.current_principal_id() is null
    and coalesce(current_setting('youjian.achievement_source',true),'')<>'scheduled_maintenance' then return new; end if;
  if new.member_limit=old.member_limit then return new; end if;
  select count(*)::integer into active_count from public.space_members
    where space_id=new.id and status='active';
  if active_count>=5 and active_count>=new.member_limit
    and at_time>=private.achievement_strategy_enabled_at('full_house') then
    select p.timezone into owner_tz from public.profiles p where p.id=new.owner_id;
    perform private.record_personal_achievement_event(
      new.owner_id,'full_house',new.id,null,
      'capacity:'||new.id::text||':'||new.member_limit::text,
      (at_time at time zone coalesce(owner_tz,new.timezone))::date,at_time,
      jsonb_build_object('member_count',active_count,'member_limit',new.member_limit)
    );
  end if;
  return new;
end $$;

drop trigger if exists spaces_catalog_capacity_achievement on public.spaces;
create trigger spaces_catalog_capacity_achievement
after update of member_limit on public.spaces
for each row execute function private.evaluate_catalog_capacity_achievement();

create or replace function private.rpc_impl_list_personal_achievements(
  p_space_id uuid,p_limit integer,p_cursor text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  a uuid:=private.current_principal_id();
  cursor_time timestamptz;
  cursor_type text;
  items jsonb;
  next_cursor text;
  v_seen_at timestamptz;
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  select max(n.personal_seen_at) into v_seen_at
  from public.achievement_nav_reads n
  join public.space_members m on m.id=n.member_id
  where m.user_id=a;
  if p_cursor is not null then begin
    cursor_time:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',1)::timestamptz;
    cursor_type:=split_part(convert_from(decode(p_cursor,'base64'),'UTF8'),'|',2);
  exception when others then return public.api_error('INVALID_CURSOR'); end; end if;
  with rows as(
    select pa.*,c.key catalog_key,c.scope,c.repeat_policy,c.stage_thresholds,
      row_number() over(order by pa.last_unlocked_at desc,pa.achievement_type desc) rn
    from public.personal_achievements pa
    left join private.achievement_strategy_catalog c on c.key=private.canonical_achievement_type(pa.achievement_type)
    where pa.user_id=a
      and (p_cursor is null or(pa.last_unlocked_at,pa.achievement_type)<(cursor_time,cursor_type))
    order by pa.last_unlocked_at desc,pa.achievement_type desc limit p_limit+1
  ), chosen as(select * from rows where rn<=p_limit), shaped as(
    select chosen.*,
      private.achievement_stage(chosen.achievement_type,chosen.count,chosen.metadata) attained_stage
    from chosen
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',achievement_type,'achievement_type',achievement_type,
    'card_key',coalesce(catalog_key,achievement_type),'raw_achievement_key',achievement_type,
    'scope','personal','attained_stage',attained_stage,
    'stage_key',(select stage->>'stage_key' from jsonb_array_elements(coalesce(stage_thresholds,'[]'::jsonb)) stage
      where (stage->>'stage')::integer=attained_stage limit 1),
    'tier',coalesce(private.achievement_tier(achievement_type,attained_stage),tier),
    'earned_at',last_unlocked_at,'first_earned_at',first_earned_at,'last_earned_at',last_earned_at,
    'last_unlocked_at',last_unlocked_at,
    'repeatable',repeat_policy in('series','daily'),'count',count,'metadata',metadata,
    'read_target',jsonb_build_object('kind','personal_tab','key','personal'),
    'seen',coalesce(v_seen_at,'-infinity'::timestamptz)>=last_unlocked_at,
    'events',(select coalesce(jsonb_agg(jsonb_build_object(
      'event_id',e.id::text,'achievement_id',e.id::text,'earned_at',e.earned_at,
      'local_date',e.local_date,'source_space_id',e.source_space_id,'metadata',e.metadata,
      'notification_eligible',e.notification_eligible,'is_unlock',e.notification_eligible,
      'is_repeat_event',not e.notification_eligible,'last_unlocked_at',case when e.notification_eligible then e.earned_at end
    ) order by e.earned_at desc,e.id desc),'[]'::jsonb)
      from public.personal_achievement_awards e
      where e.user_id=a and e.achievement_type=shaped.achievement_type and e.notification_eligible)
  ) order by last_unlocked_at desc,achievement_type desc),'[]'::jsonb),
  case when(select count(*) from rows)>p_limit then
    (select encode(convert_to(last_unlocked_at::text||'|'||achievement_type,'UTF8'),'base64')
      from chosen order by last_unlocked_at,achievement_type limit 1) end
  into items,next_cursor from shaped;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',next_cursor));
end $$;

create or replace function private.rpc_impl_list_achievements(
  p_space_id uuid,p_limit integer,p_cursor text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); m uuid; items jsonb;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_limit is null or p_limit<1 or p_limit>100 then return public.api_error('INVALID_LIMIT'); end if;
  if p_cursor is not null then return public.api_error('INVALID_CURSOR'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  with raw as(
    select ac.*,private.canonical_achievement_type(ac.achievement_type) card_type,
      row_number() over(partition by private.canonical_achievement_type(ac.achievement_type)
        order by ac.earned_at,ac.id) legacy_rank
    from public.achievements ac
    where ac.space_id=p_space_id and ac.achievement_type<>'together_lit'
  ), base as(
    select r.*,c.* from raw r left join private.achievement_strategy_catalog c on c.key=r.card_type
    where (c.scope='shared' or c.key is null)
      and not(r.achievement_type in('three_days_together','three_day_together') and exists(
        select 1 from raw x where x.card_type='together_streak' and x.achievement_type='together_streak'))
      and not(r.achievement_type='first_goal' and exists(
        select 1 from raw x where x.card_type='goal_milestone' and x.achievement_type='goal_milestone'))
      and (c.legacy_aliases is null or not(r.achievement_type=any(c.legacy_aliases) and r.legacy_rank>1))
      and (c.metric is null or c.metric<>'threshold_minutes' or private.achievement_stage(r.card_type,1,r.metadata)>0)
  ), ranked as(
    select b.*,row_number() over(partition by b.card_type order by b.notification_eligible desc,
      b.earned_at desc,b.id desc) pick,
      count(*) over(partition by b.card_type) event_count,
      min(b.earned_at) over(partition by b.card_type) first_at,
      max(b.earned_at) over(partition by b.card_type) last_at,
      max(b.earned_at) filter(where b.notification_eligible) over(partition by b.card_type) last_unlock_at,
      max(private.achievement_stage(b.card_type,1,b.metadata)) over(partition by b.card_type) attained_stage
    from base b
  ), cards as(
    select * from ranked where pick=1 and last_unlock_at is not null
    order by last_unlock_at desc,card_type desc limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'achievement_id',cards.id::text,'achievement_type',cards.card_type,
    'card_key',cards.card_type,'raw_achievement_key',cards.achievement_type,
    'scope','shared','attained_stage',cards.attained_stage,
    'stage_key',(select stage->>'stage_key' from jsonb_array_elements(coalesce(cards.stage_thresholds,'[]'::jsonb)) stage
      where (stage->>'stage')::integer=cards.attained_stage limit 1),
    'tier',case when cards.attained_stage=0 then cards.tier
      else private.achievement_tier(cards.card_type,cards.attained_stage) end,
    'earned_at',cards.last_unlock_at,'first_earned_at',cards.first_at,'last_earned_at',cards.last_at,
    'last_unlocked_at',cards.last_unlock_at,'repeatable',cards.repeat_policy in('series','daily'),
    'count',cards.event_count,'metadata',cards.metadata,'participants_recorded',true,
    'read_target',case when cards.key is null then null
      else jsonb_build_object('kind','shared_card','key',cards.card_type) end,
    'seen',not exists(select 1 from base unread where unread.card_type=cards.card_type
      and unread.notification_eligible and not exists(
        select 1 from public.achievement_reads ar where ar.achievement_id=unread.id and ar.member_id=m)),
    'participants',(select coalesce(jsonb_agg(jsonb_build_object(
      'member_id',p.member_id,'display_name',p.display_name_snapshot,'participation_days',p.participation_days)
      order by p.display_name_snapshot),'[]'::jsonb) from(
        select ap.member_id,max(ap.display_name_snapshot) display_name_snapshot,max(ap.participation_days) participation_days
        from public.achievement_participants ap join base pb on pb.id=ap.achievement_id
        where pb.card_type=cards.card_type group by ap.member_id
      ) p),
    'events',(select coalesce(jsonb_agg(jsonb_build_object(
      'event_id',ev.id::text,'achievement_id',ev.id::text,'earned_at',ev.earned_at,
      'metadata',ev.metadata,'notification_eligible',ev.notification_eligible,
      'is_unlock',ev.notification_eligible,'is_repeat_event',not ev.notification_eligible,
      'raw_achievement_key',ev.achievement_type,
      'participants',(select coalesce(jsonb_agg(jsonb_build_object('member_id',ep.member_id,
        'display_name',ep.display_name_snapshot,'participation_days',ep.participation_days)
        order by ep.display_name_snapshot),'[]'::jsonb)
        from public.achievement_participants ep where ep.achievement_id=ev.id)
    ) order by ev.earned_at desc,ev.id desc),'[]'::jsonb)
      from base ev where ev.card_type=cards.card_type and ev.notification_eligible)
  ) order by cards.last_unlock_at desc,cards.card_type desc),'[]'::jsonb)
  into items from cards;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,'items',items,'next_cursor',null));
end $$;

create or replace function private.rpc_impl_mark_achievement_tab_seen(p_space_id uuid,p_tab text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); m uuid;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  if p_tab not in('personal','shared') then return public.api_error('INVALID_ACHIEVEMENT_TAB'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  insert into public.achievement_nav_reads(member_id,personal_seen_at,shared_seen_at)
  values(m,case when p_tab='personal' then now() else '-infinity' end,
    case when p_tab='shared' then now() else '-infinity' end)
  on conflict(member_id) do update set
    personal_seen_at=case when p_tab='personal' then now() else public.achievement_nav_reads.personal_seen_at end,
    shared_seen_at=case when p_tab='shared' then now() else public.achievement_nav_reads.shared_seen_at end;
  return public.api_ok(jsonb_build_object('tab',p_tab,'seen',true));
end $$;

create or replace function public.mark_achievement_card_seen(
  p_space_id uuid,p_card_key text,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  a uuid:=private.current_principal_id();
  m uuid;
  canonical text:=private.canonical_achievement_type(p_card_key);
  strategy private.achievement_strategy_catalog%rowtype;
  cached jsonb;
  result jsonb;
  h text:=coalesce(p_space_id::text,'')||'|'||coalesce(p_card_key,'');
begin
  if a is null then return public.api_error('AUTH_REQUIRED'); end if;
  if p_idempotency_key is null then return public.api_error('INVALID_IDEMPOTENCY_KEY'); end if;
  cached:=public.command_cached(a,p_idempotency_key,'mark_achievement_card_seen',h);
  if cached is not null then return cached; end if;
  select * into strategy from private.achievement_strategy_catalog where key=canonical;
  if not found or strategy.scope<>'shared' then return public.api_error('ACHIEVEMENT_NOT_FOUND'); end if;
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  insert into public.achievement_reads(achievement_id,member_id)
  select ac.id,m from public.achievements ac
  where ac.space_id=p_space_id and ac.notification_eligible
    and private.canonical_achievement_type(ac.achievement_type)=canonical
  on conflict(achievement_id,member_id) do nothing;
  result:=public.api_ok(jsonb_build_object('card_key',canonical,'seen',true));
  return public.store_command(a,p_idempotency_key,'mark_achievement_card_seen',h,null,result);
end $$;

create or replace function private.rpc_impl_get_nav_notifications(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a uuid:=private.current_principal_id(); m uuid; personal_seen timestamptz;
begin
  if not public.current_user_is_active_member(p_space_id) then return public.api_error('SPACE_ACCESS_DENIED'); end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  insert into public.achievement_nav_reads(member_id) values(m) on conflict do nothing;
  select personal_seen_at into personal_seen from public.achievement_nav_reads where member_id=m;
  return public.api_ok(jsonb_build_object('space_id',p_space_id,
    'personal',exists(select 1 from public.personal_achievements pa
      where pa.user_id=a and pa.last_unlocked_at>personal_seen),
    'shared',exists(select 1 from public.achievements ac
      left join private.achievement_strategy_catalog c on c.key=private.canonical_achievement_type(ac.achievement_type)
      where ac.space_id=p_space_id and (c.scope='shared' or c.key is null) and ac.notification_eligible
        and (c.legacy_aliases is null or not(ac.achievement_type=any(c.legacy_aliases)))
        and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=ac.id and ar.member_id=m)),
    'proposal',exists(select 1 from public.goal_proposal_members pm join public.goal_proposals p on p.id=pm.proposal_id
      where pm.member_id=m and pm.vote is null and p.status='pending')));
end $$;

create or replace function private.rpc_impl_get_home_snapshot(p_space_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  result jsonb;
  a uuid:=private.current_principal_id();
  m uuid;
  v_seen_at timestamptz;
  personal jsonb;
  shared jsonb;
begin
  result:=private.legacy_get_home_snapshot_before_personal_achievements(p_space_id);
  if result->>'ok'<>'true' then return result; end if;
  select id into m from public.space_members where space_id=p_space_id and user_id=a and status='active';
  select jsonb_build_object(
      'achievement_id',ac.id::text,'achievement_type',private.canonical_achievement_type(ac.achievement_type),
      'card_key',private.canonical_achievement_type(ac.achievement_type),'raw_achievement_key',ac.achievement_type,
      'scope','shared','attained_stage',private.achievement_stage(ac.achievement_type,1,ac.metadata),
      'tier',private.achievement_tier(ac.achievement_type,private.achievement_stage(ac.achievement_type,1,ac.metadata)),
      'earned_at',ac.earned_at,'metadata',ac.metadata,'event_id',ac.id::text,
      'notification_eligible',ac.notification_eligible,'is_unlock',ac.notification_eligible,
      'read_target',case when c.key is null then null
        else jsonb_build_object('kind','shared_card','key',private.canonical_achievement_type(ac.achievement_type)) end
    ) into shared
  from public.achievements ac
  left join private.achievement_strategy_catalog c on c.key=private.canonical_achievement_type(ac.achievement_type)
  where ac.space_id=p_space_id and (c.scope='shared' or c.key is null) and ac.notification_eligible
    and (c.legacy_aliases is null or not(ac.achievement_type=any(c.legacy_aliases)))
    and not exists(select 1 from public.achievement_reads ar where ar.achievement_id=ac.id and ar.member_id=m)
  order by ac.earned_at,ac.id limit 1;
  result:=jsonb_set(result,'{data,unseen_achievement}',coalesce(shared,'null'::jsonb),true);
  select max(n.personal_seen_at) into v_seen_at
  from public.achievement_nav_reads n join public.space_members sm on sm.id=n.member_id where sm.user_id=a;
  select jsonb_build_object(
      'achievement_id',pa.achievement_type,'achievement_type',pa.achievement_type,
      'card_key',pa.achievement_type,'raw_achievement_key',pa.achievement_type,'scope','personal',
      'attained_stage',private.achievement_stage(pa.achievement_type,pa.count,pa.metadata),
      'tier',pa.tier,'earned_at',pa.last_unlocked_at,'first_earned_at',pa.first_earned_at,
      'last_earned_at',pa.last_earned_at,'last_unlocked_at',pa.last_unlocked_at,
      'count',pa.count,'metadata',pa.metadata,'seen',false,
      'read_target',jsonb_build_object('kind','personal_tab','key','personal')
    ) into personal
  from public.personal_achievements pa
  where pa.user_id=a and pa.last_unlocked_at>coalesce(v_seen_at,'-infinity'::timestamptz)
  order by pa.last_unlocked_at,pa.achievement_type limit 1;
  return jsonb_set(result,'{data,unseen_personal_achievement}',coalesce(personal,'null'::jsonb),true);
end $$;

-- Normal authenticated sessions resolve to the stable principal. The raw
-- auth id fallback keeps local SQL/pgTAP fixtures and freshly-created
-- identities readable before the binding trigger is visible to the session;
-- it does not alter the recovery binding itself.
drop policy if exists personal_achievements_select_own on public.personal_achievements;
create policy personal_achievements_select_own
on public.personal_achievements for select to authenticated
using (user_id=(select private.current_principal_id()));

drop policy if exists personal_achievement_awards_select_own on public.personal_achievement_awards;
create policy personal_achievement_awards_select_own
on public.personal_achievement_awards for select to authenticated
using (user_id=(select private.current_principal_id()));

revoke all on table private.achievement_strategy_catalog from public,anon,authenticated;
revoke all on function private.canonical_achievement_type(text),private.achievement_strategy_enabled_at(text),
  private.achievement_stage(text,integer,jsonb),private.achievement_tier(text,integer),private.personal_tier(text,integer,jsonb),
  private.record_personal_achievement_event(uuid,text,uuid,uuid,text,date,timestamptz,jsonb),
  private.record_personal_achievement(uuid,text,uuid,uuid,timestamptz),private.shared_achievement_tier(text,integer),
  private.record_shared_achievement_event(uuid,text,text,timestamptz,text,jsonb,uuid[]),
  private.evaluate_catalog_personal_focus_achievements(),private.evaluate_catalog_task_revision_achievement(),
  private.evaluate_catalog_global_timezones(),private.evaluate_catalog_membership_achievements(),
  private.evaluate_catalog_capacity_achievement(),private.rpc_impl_list_personal_achievements(uuid,integer,text),
  private.rpc_impl_list_achievements(uuid,integer,text),private.rpc_impl_mark_achievement_tab_seen(uuid,text),
  private.rpc_impl_get_nav_notifications(uuid),private.rpc_impl_get_home_snapshot(uuid)
from public,anon,authenticated;
revoke all on function public.mark_achievement_card_seen(uuid,text,uuid) from public,anon;
grant execute on function public.mark_achievement_card_seen(uuid,text,uuid) to authenticated;
grant execute on function public.current_user_is_active_member(uuid),public.current_user_is_owner(uuid) to authenticated;
grant execute on function public.get_nav_notifications(uuid),public.mark_achievement_tab_seen(uuid,text) to authenticated;
