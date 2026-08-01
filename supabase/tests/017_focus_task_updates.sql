begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000171'),
 ('00000000-0000-0000-0000-000000000172');
insert into public.profiles(id,timezone) values
 ('00000000-0000-0000-0000-000000000171','UTC'),
 ('00000000-0000-0000-0000-000000000172','UTC');
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash) values
 ('10000000-0000-0000-0000-000000000171','Task updates','00000000-0000-0000-0000-000000000171','UTC','task-update-hash');
insert into public.space_members(id,space_id,user_id,display_name,role) values
 ('20000000-0000-0000-0000-000000000171','10000000-0000-0000-0000-000000000171','00000000-0000-0000-0000-000000000171','Owner','owner'),
 ('20000000-0000-0000-0000-000000000172','10000000-0000-0000-0000-000000000171','00000000-0000-0000-0000-000000000172','Friend','member');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select is(public.start_focus('10000000-0000-0000-0000-000000000171','Original','study','30000000-0000-0000-0000-000000000171')#>>'{data,session,status}','focusing','owner starts a focus session');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Original'),'Revised','work','30000000-0000-0000-0000-000000000172')#>>'{data,session,task_name}','Revised','focusing task name updates');
select is((select category::text from public.focus_sessions where task_name='Revised'),'work','category updates with task');
select is((select count(*)::int from public.focus_events where event_type='task_updated'),1,'one immutable update event is appended');
reset role;
select is(public.session_json((select id from public.focus_sessions where task_name='Revised'))#>>'{task_history,0,task_name}','Original','session history contains prior task');
select is(public.session_json((select id from public.focus_sessions where task_name='Revised'))#>>'{task_history,0,category}','study','session history contains prior category');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Revised'),'Revised','work','30000000-0000-0000-0000-000000000173')#>>'{data,session,task_name}','Revised','unchanged submission succeeds');
select is((select count(*)::int from public.focus_events where event_type='task_updated'),1,'unchanged submission adds no event');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Revised'),'Final','reading','30000000-0000-0000-0000-000000000174')#>>'{data,session,task_history,0,task_name}','Revised','multiple updates return newest prior version first');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000172',true);
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000171')#>>'{data,focusing_members,0,task_history,0,task_name}','Revised','friend snapshot exposes the shared task history');
reset role;
update public.focus_sessions set active_segment_started_at=now()-interval '60 seconds' where task_name='Final';
update public.focus_segments set started_at=now()-interval '60 seconds' where ended_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select is(public.pause_focus((select id from public.focus_sessions where task_name='Final'),'30000000-0000-0000-0000-000000000175')#>>'{data,session,status}','paused','session pauses');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Final'),'Paused edit','other','30000000-0000-0000-0000-000000000176')#>>'{data,session,task_name}','Paused edit','paused task updates');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Paused edit'),'','other','30000000-0000-0000-0000-000000000177')#>>'{error,code}','INVALID_TASK_NAME','blank task is rejected');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Paused edit'),'Invalid category','invalid','30000000-0000-0000-0000-000000000178')#>>'{error,code}','INVALID_CATEGORY','invalid category is rejected');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000172',true);
select is(public.get_home_snapshot('10000000-0000-0000-0000-000000000171')#>>'{data,focusing_members}','[]','paused sessions are not shown as currently focusing friends');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Paused edit'),'Hijacked','work','30000000-0000-0000-0000-000000000179')#>>'{error,code}','SESSION_NOT_FOUND','another member cannot edit or enumerate the task');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000171',true);
select lives_ok($$select public.end_focus((select id from public.focus_sessions where task_name='Paused edit'),'30000000-0000-0000-0000-000000000180')$$,'session can be settled');
select is(public.update_focus_task((select id from public.focus_sessions where task_name='Paused edit'),'Too late','work','30000000-0000-0000-0000-000000000181')#>>'{error,code}','SESSION_NOT_ACTIVE','settled task remains immutable');

select * from finish();
rollback;
