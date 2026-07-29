begin;
create extension if not exists pgtap with schema extensions;
select plan(19);
insert into auth.users(id) values('00000000-0000-0000-0000-000000000061');
insert into public.profiles(id,timezone) values('00000000-0000-0000-0000-000000000061','Asia/Shanghai');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values('10000000-0000-0000-0000-000000000061','Stats','00000000-0000-0000-0000-000000000061','Asia/Shanghai','stats');
insert into public.space_members(id,space_id,user_id,display_name,role) values('20000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','Analyst','owner');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,category,status,accumulated_focus_seconds,started_at,completed_at,completion_reason,last_seen_at) values
 ('40000000-0000-0000-0000-000000000061','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','Cross midnight','study','completed',1800,'2026-07-27 15:50Z','2026-07-27 16:20Z','manual_end','2026-07-27 16:20Z'),
 ('40000000-0000-0000-0000-000000000062','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','Discarded','study','discarded',299,'2026-07-27 10:00Z','2026-07-27 10:04:59Z','manual_end','2026-07-27 10:04:59Z');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000061','2026-07-27 15:50Z','2026-07-27 16:20Z'),
 ('40000000-0000-0000-0000-000000000062','2026-07-27 10:00Z','2026-07-27 10:04:59Z');
select is(public.credited_seconds_for_day('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','2026-07-27','Asia/Shanghai'),600,'cross-midnight segment credits first local day');
select is(public.credited_seconds_for_day('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','2026-07-28','Asia/Shanghai'),1200,'cross-midnight segment credits second local day');
select is(public.credited_seconds_for_day('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','2026-07-27','UTC'),1800,'same segment respects requested timezone');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000061',true);
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000061','mine','daily','2026-07-27')#>>'{data,credited_focus_seconds}','600','daily summary uses profile timezone');
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000061','mine','weekly','2026-07-27')#>>'{data,valid_session_count}','1','valid session counted once across segments');
select is(jsonb_array_length(public.get_stats_summary('10000000-0000-0000-0000-000000000061','mine','weekly','2026-07-27')#>'{data,days}'),7,'weekly summary contains seven local days');
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000061','mine','daily','2026-07-27')#>>'{data,checkin_day_count}','0','sub-hour day does not check in');
select is(jsonb_array_length(public.list_focus_history('10000000-0000-0000-0000-000000000061','mine','2026-07-01Z','2026-08-01Z',30,null)#>'{data,items}'),2,'history includes completed and discarded records');
select is(public.list_focus_history('10000000-0000-0000-0000-000000000061','mine','2026-07-01Z','2026-08-01Z',30,null)#>>'{data,items,0,counts_toward_stats}','true','completed history counts toward stats');
select ok(not ((public.get_focus_session_detail('40000000-0000-0000-0000-000000000061')#>'{data}') ? 'events'),'detail excludes raw event metadata');
select is(jsonb_array_length(public.get_focus_session_detail('40000000-0000-0000-0000-000000000061')#>'{data,segments}'),1,'detail exposes factual segments');

insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason,last_seen_at) values
 ('40000000-0000-0000-0000-000000000063','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','Paris spring','completed',21600,'2026-03-28 23:00Z','2026-03-29 05:00Z','manual_end','2026-03-29 05:00Z'),
 ('40000000-0000-0000-0000-000000000064','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','NY fall','completed',21600,'2026-11-01 04:00Z','2026-11-01 10:00Z','manual_end','2026-11-01 10:00Z');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000063','2026-03-28 23:00Z','2026-03-29 05:00Z'),('40000000-0000-0000-0000-000000000064','2026-11-01 04:00Z','2026-11-01 10:00Z');
select is(extract(epoch from(('2026-03-30'::date::timestamp at time zone 'Europe/Paris')-('2026-03-29'::date::timestamp at time zone 'Europe/Paris')))::int,82800,'Paris spring DST day is 23 hours');
select is(extract(epoch from(('2026-11-02'::date::timestamp at time zone 'America/New_York')-('2026-11-01'::date::timestamp at time zone 'America/New_York')))::int,90000,'New York fall DST day is 25 hours');
select is(public.credited_seconds_for_day('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','2026-03-29','Europe/Paris'),21600,'spring DST aggregation uses timezone database');
select is(public.credited_seconds_for_day('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','2026-11-01','America/New_York'),21600,'fall DST aggregation uses timezone database');
select is(public.get_stats_summary('10000000-0000-0000-0000-000000000061','mine','bogus','2026-07-27')#>>'{error,code}','INVALID_PERIOD','invalid period is rejected');
select is(public.get_focus_session_detail('40000000-0000-0000-0000-000000000999')#>>'{error,code}','SESSION_NOT_FOUND','unauthorized id does not disclose existence');
insert into public.focus_sessions(id,space_id,user_id,member_id,task_name,status,accumulated_focus_seconds,started_at,completed_at,completion_reason,last_seen_at) values
 ('40000000-0000-0000-0000-000000000065','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','Streak day one','completed',3600,'2026-07-25 01:00Z','2026-07-25 02:00Z','manual_end','2026-07-25 02:00Z'),
 ('40000000-0000-0000-0000-000000000066','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','Streak day two','completed',3600,'2026-07-26 01:00Z','2026-07-26 02:00Z','manual_end','2026-07-26 02:00Z'),
 ('40000000-0000-0000-0000-000000000067','10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','20000000-0000-0000-0000-000000000061','Streak day three remainder','completed',3000,'2026-07-27 01:00Z','2026-07-27 01:50Z','manual_end','2026-07-27 01:50Z');
insert into public.focus_segments(session_id,started_at,ended_at) values
 ('40000000-0000-0000-0000-000000000065','2026-07-25 01:00Z','2026-07-25 02:00Z'),
 ('40000000-0000-0000-0000-000000000066','2026-07-26 01:00Z','2026-07-26 02:00Z'),
 ('40000000-0000-0000-0000-000000000067','2026-07-27 01:00Z','2026-07-27 01:50Z');
select is(public.current_streak_days('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','Asia/Shanghai','2026-07-27 12:00Z'),3,'set-based streak includes a qualifying current day');
select is(public.current_streak_days('10000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000061','Asia/Shanghai','2026-07-28 12:00Z'),3,'set-based streak falls back to yesterday when today is below target');
select * from finish(); rollback;
