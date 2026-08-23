alter type public.focus_category add value if not exists 'life';

insert into private.achievement_strategy_catalog(
  key,scope,repeat_policy,event_unit,metric,max_stage_behavior,
  notification_policy,participant_policy,time_boundary,evaluator_id,
  counter_scope,event_key_policy,activation_boundary,display_policy,read_target,
  series,icon,condition,legacy_aliases,stage_thresholds,tier_policy
) values(
  'orderly_living','personal','once','session','count','ignore_after_unlock',
  'first_unlock','owner','none','focus.category_session','user_lifetime',
  'focus_session_id','catalog_v1','attained_stage_only','personal_tab','',
  'cog','完成 10 次最终类型为“生活”的有效专注 session。','{}',
  '[{"stage":1,"threshold":10,"stage_key":"orderly_living","title":"井井有条"}]',
  '{"kind":"fixed","tier":"gold"}'
);

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
    when 'life' then 'orderly_living'
    when 'entertainment' then 'joyful_pursuit'
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
