begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000221'),
 ('00000000-0000-0000-0000-000000000222');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000221','Asia/Shanghai'),
 ('00000000-0000-0000-0000-000000000222','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000221','Summary counts','00000000-0000-0000-0000-000000000221','Asia/Shanghai','summary-counts'),
 ('10000000-0000-0000-0000-000000000222','Legacy fallback','00000000-0000-0000-0000-000000000221','Asia/Shanghai','legacy-fallback');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000221','10000000-0000-0000-0000-000000000221','00000000-0000-0000-0000-000000000221','jade','owner'),
 ('20000000-0000-0000-0000-000000000222','10000000-0000-0000-0000-000000000221','00000000-0000-0000-0000-000000000222','JU','member'),
 ('20000000-0000-0000-0000-000000000223','10000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000221','jade','owner');

insert into public.achievements(id,space_id,achievement_type,dedupe_key,earned_at,metadata,tier,participants_recorded) values
 ('70000000-0000-0000-0000-000000000221','10000000-0000-0000-0000-000000000221','together_streak','test:together:1','2026-08-02 00:00:00+00','{"days":1,"period_end_date":"2026-08-02"}','bronze',true),
 ('70000000-0000-0000-0000-000000000222','10000000-0000-0000-0000-000000000221','together_streak','test:together:3','2026-08-04 00:00:00+00','{"days":3,"period_end_date":"2026-08-04"}','silver',true),
 ('70000000-0000-0000-0000-000000000223','10000000-0000-0000-0000-000000000221','three_days_together','test:legacy:together','2026-08-04 00:00:01+00','{"period_end_date":"2026-08-04"}','bronze',false),
 ('70000000-0000-0000-0000-000000000224','10000000-0000-0000-0000-000000000221','goal_milestone','test:goal:1','2026-08-05 00:00:00+00','{"completed_goal_count":1}','bronze',true),
 ('70000000-0000-0000-0000-000000000225','10000000-0000-0000-0000-000000000221','first_goal','test:legacy:goal','2026-08-05 00:00:01+00','{}','bronze',false),
 ('70000000-0000-0000-0000-000000000226','10000000-0000-0000-0000-000000000222','three_days_together','test:legacy:fallback','2026-08-03 00:00:00+00','{"period_end_date":"2026-08-03"}','silver',false),
 ('70000000-0000-0000-0000-000000000227','10000000-0000-0000-0000-000000000222','three_days_together','test:legacy:fallback:repeat','2026-08-04 00:00:00+00','{"period_end_date":"2026-08-04"}','silver',false);
insert into public.achievement_participants(achievement_id,member_id,display_name_snapshot) values
 ('70000000-0000-0000-0000-000000000221','20000000-0000-0000-0000-000000000221','jade'),
 ('70000000-0000-0000-0000-000000000221','20000000-0000-0000-0000-000000000222','JU'),
 ('70000000-0000-0000-0000-000000000222','20000000-0000-0000-0000-000000000221','jade'),
 ('70000000-0000-0000-0000-000000000222','20000000-0000-0000-0000-000000000222','JU');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000221',true);

select is(
  jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000221',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "together_streak")')->>'count',
  '2','series count excludes the equivalent legacy three-day row');
select is(
  jsonb_array_length(jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000221',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "together_streak")')->'events'),
  2,'series event history uses the same normalized rows as its count');
select is(
  jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000221',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "together_streak")')->>'tier',
  'silver','series card keeps the highest canonical tier');
select is(
  jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000221',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "together_streak")')->'metadata'->>'days',
  '3','series card keeps the highest canonical stage');
select is(
  jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000221',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "goal_milestone")')->>'count',
  '1','first-goal compatibility row does not duplicate the canonical milestone');
select is(
  jsonb_array_length(jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000221',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "goal_milestone")')->'events'),
  1,'goal milestone count and event history stay consistent');
select is(
  jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000222',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "together_streak")')->>'count',
  '1','legacy-only rolling three-day rows collapse to one series-stage fallback');
select is(
  jsonb_path_query_first(public.list_achievements('10000000-0000-0000-0000-000000000222',30,null)#>'{data,items}', '$[*] ? (@.achievement_type == "together_streak")')->>'tier',
  'silver','legacy fallback preserves its stored tier');

select * from finish();
rollback;
