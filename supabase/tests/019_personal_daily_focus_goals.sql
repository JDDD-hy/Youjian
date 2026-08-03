begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000191'),
 ('00000000-0000-0000-0000-000000000192');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000191','UTC'),
 ('00000000-0000-0000-0000-000000000192','UTC');
insert into public.spaces(id,name,owner_id,timezone,daily_checkin_target_minutes,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000191','Personal goals','00000000-0000-0000-0000-000000000191','UTC',60,'personal-goals');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000191','10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191','Owner','owner');

select is(public.personal_goal_minutes('10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191',current_date),60,'space target is the migration fallback');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select is(public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','today',29,'30000000-0000-0000-0000-000000000191')#>>'{error,code}','INVALID_DAILY_GOAL_TARGET','target below thirty minutes is rejected');
select is(public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','today',45,'30000000-0000-0000-0000-000000000192')#>>'{data,effective_date}',current_date::text,'today override uses the profile local date');
select is(
 public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','today',45,'30000000-0000-0000-0000-000000000192'),
 public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','today',45,'30000000-0000-0000-0000-000000000192'),
 'today override retry returns the cached idempotent response'
);
reset role;
select is(public.personal_goal_minutes('10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191',current_date),45,'today override wins');
select is(public.personal_goal_minutes('10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191',current_date+1),60,'today override does not change tomorrow');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select is(public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','future_default',90,'30000000-0000-0000-0000-000000000193')#>>'{data,effective_date}',(current_date+1)::text,'repeating default starts tomorrow');
reset role;
select is(public.personal_goal_minutes('10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191',current_date),45,'future default does not rewrite today');
select is(public.personal_goal_minutes('10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191',current_date+1),90,'future default applies tomorrow');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000191')#>>'{data,today,goal_source}','today_override','home reports override provenance');
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000191')#>>'{data,today,goal_locked}','false','today remains editable before first focus');
reset role;
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason,last_seen_at) values
 ('40000000-0000-0000-0000-000000000191','10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191','20000000-0000-0000-0000-000000000191','Reached personal goal','completed',2700,now()-interval '45 minutes',now(),'manual_end',now());
insert into public.focus_segments(session_id,started_at,ended_at) values('40000000-0000-0000-0000-000000000191',now()-interval '45 minutes',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000191','mine','daily',current_date)#>>'{data,days,0,checkin_completed}','true','personal stats use the effective forty-five minute goal instead of the space fallback');
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000191')#>>'{data,today,current_streak_days}','1','personal streak uses the effective historical goal');
select is(public.start_focus('10000000-0000-0000-0000-000000000191','Lock today','study','30000000-0000-0000-0000-000000000194')#>>'{data,session,status}','focusing','first focus starts');
select is(public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','today',60,'30000000-0000-0000-0000-000000000195')#>>'{error,code}','DAILY_GOAL_LOCKED','today is locked after any focus starts');
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000191')#>>'{data,today,goal_locked}','true','home exposes the authoritative lock');
select is(public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','future_default',75,'30000000-0000-0000-0000-000000000196')#>>'{data,target_minutes}','75','future default remains editable after focus starts');
reset role;
select is(public.personal_goal_minutes('10000000-0000-0000-0000-000000000191','00000000-0000-0000-0000-000000000191',current_date+1),75,'latest future default is resolved without changing history');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select throws_ok($$select * from public.personal_focus_goal_defaults$$,'42501',null,'authenticated clients cannot read goal history tables directly');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select is(public.set_personal_daily_goal('10000000-0000-0000-0000-000000000191','today',30,'30000000-0000-0000-0000-000000000197')#>>'{error,code}','SPACE_ACCESS_DENIED','non-members cannot edit a goal in the space');

select * from finish();
rollback;
