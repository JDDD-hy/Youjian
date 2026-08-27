begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000321'),
  ('00000000-0000-0000-0000-000000000322');
insert into public.profiles(id, timezone) values
  ('00000000-0000-0000-0000-000000000321', 'UTC'),
  ('00000000-0000-0000-0000-000000000322', 'UTC');
insert into public.spaces(id, name, owner_id, timezone, invite_token_hash) values
  ('10000000-0000-0000-0000-000000000321', 'History A', '00000000-0000-0000-0000-000000000321', 'UTC', 'history-a'),
  ('10000000-0000-0000-0000-000000000322', 'History B', '00000000-0000-0000-0000-000000000322', 'UTC', 'history-b');
insert into public.space_members(id, space_id, user_id, display_name, role) values
  ('20000000-0000-0000-0000-000000000321', '10000000-0000-0000-0000-000000000321', '00000000-0000-0000-0000-000000000321', 'Owner A', 'owner'),
  ('20000000-0000-0000-0000-000000000322', '10000000-0000-0000-0000-000000000322', '00000000-0000-0000-0000-000000000322', 'Owner B', 'owner');

insert into public.goal_proposals(
  id, space_id, proposer_member_id, goal_type, period_type, target_value,
  status, expires_at, effective_period_start, created_at, resolved_at
) values
  ('50000000-0000-0000-0000-000000000321', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 1, 'accepted', '2026-08-01 01:00Z', '2026-08-02 00:00Z', '2026-08-01 00:00Z', '2026-08-01 00:30Z'),
  ('50000000-0000-0000-0000-000000000322', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 2, 'accepted', '2026-08-02 01:00Z', '2026-08-03 00:00Z', '2026-08-02 00:00Z', '2026-08-02 00:30Z'),
  ('50000000-0000-0000-0000-000000000323', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 3, 'accepted', '2026-08-03 01:00Z', '2026-08-04 00:00Z', '2026-08-03 00:00Z', '2026-08-03 00:30Z'),
  ('50000000-0000-0000-0000-000000000324', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 4, 'accepted', '2026-08-04 01:00Z', '2026-08-05 00:00Z', '2026-08-04 00:00Z', '2026-08-04 00:30Z'),
  ('50000000-0000-0000-0000-000000000325', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 5, 'accepted', '2026-08-05 01:00Z', '2026-08-06 00:00Z', '2026-08-05 00:00Z', '2026-08-05 00:30Z'),
  ('50000000-0000-0000-0000-000000000331', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'weekly', 11, 'rejected', '2026-08-11 01:00Z', '2026-08-17 00:00Z', '2026-08-11 00:00Z', '2026-08-12 00:30Z'),
  ('50000000-0000-0000-0000-000000000332', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'weekly', 12, 'expired', '2026-08-12 01:00Z', '2026-08-17 00:00Z', '2026-08-12 00:00Z', '2026-08-12 00:30Z'),
  ('50000000-0000-0000-0000-000000000333', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'weekly', 13, 'rejected', '2026-08-13 01:00Z', '2026-08-17 00:00Z', '2026-08-13 00:00Z', '2026-08-13 00:30Z'),
  ('50000000-0000-0000-0000-000000000334', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'weekly', 14, 'expired', '2026-08-14 01:00Z', '2026-08-17 00:00Z', '2026-08-14 00:00Z', '2026-08-14 00:30Z'),
  ('50000000-0000-0000-0000-000000000335', '10000000-0000-0000-0000-000000000321', '20000000-0000-0000-0000-000000000321', 'group_total_minutes', 'weekly', 15, 'rejected', '2026-08-15 01:00Z', '2026-08-17 00:00Z', '2026-08-15 00:00Z', '2026-08-15 00:30Z');

insert into public.goals(
  id, source_proposal_id, space_id, goal_type, period_type, target_value,
  starts_at, ends_at, status, completed_at
) values
  ('60000000-0000-0000-0000-000000000321', '50000000-0000-0000-0000-000000000321', '10000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 1, '2026-08-01 00:00Z', '2026-08-02 00:00Z', 'completed', '2026-08-02 00:00Z'),
  ('60000000-0000-0000-0000-000000000322', '50000000-0000-0000-0000-000000000322', '10000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 2, '2026-08-02 00:00Z', '2026-08-04 00:00Z', 'failed', '2026-08-04 00:00Z'),
  ('60000000-0000-0000-0000-000000000323', '50000000-0000-0000-0000-000000000323', '10000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 3, '2026-08-03 00:00Z', '2026-08-04 00:00Z', 'completed', '2026-08-04 00:00Z'),
  ('60000000-0000-0000-0000-000000000324', '50000000-0000-0000-0000-000000000324', '10000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 4, '2026-08-04 00:00Z', '2026-08-05 00:00Z', 'failed', '2026-08-05 00:00Z'),
  ('60000000-0000-0000-0000-000000000325', '50000000-0000-0000-0000-000000000325', '10000000-0000-0000-0000-000000000321', 'group_total_minutes', 'daily', 5, '2026-08-05 00:00Z', '2026-08-06 00:00Z', 'completed', '2026-08-06 00:00Z');
insert into public.goal_participants(goal_id, member_id)
select id, '20000000-0000-0000-0000-000000000321'::uuid
from public.goals where space_id = '10000000-0000-0000-0000-000000000321';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000321', true);

create temporary table first_goals as
select public.list_goal_history('10000000-0000-0000-0000-000000000321', 3, null) result;
select is(jsonb_array_length((select result#>'{data,items}' from first_goals)), 3, 'goal history returns three items');
select is((select result#>>'{data,items,0,target_value}' from first_goals), '5', 'goal history is newest first');
select ok((select result#>>'{data,next_cursor}' from first_goals) is not null, 'goal history exposes a next cursor');
select is(
  jsonb_array_length(public.list_goal_history(
    '10000000-0000-0000-0000-000000000321', 3,
    (select result#>>'{data,next_cursor}' from first_goals)
  )#>'{data,items}'),
  2,
  'goal history cursor returns the remaining items'
);
select is(
  public.list_goal_history(
    '10000000-0000-0000-0000-000000000321', 3,
    (select result#>>'{data,next_cursor}' from first_goals)
  )#>>'{data,items,0,target_value}',
  '2',
  'goal history cursor resumes after the first page'
);

create temporary table first_proposals as
select public.list_goal_proposal_history('10000000-0000-0000-0000-000000000321', 4, null) result;
select is(jsonb_array_length((select result#>'{data,items}' from first_proposals)), 4, 'proposal history returns four items');
select is((select result#>>'{data,items,0,target_value}' from first_proposals), '15', 'proposal history is newest first');
select ok((select result#>>'{data,next_cursor}' from first_proposals) is not null, 'proposal history exposes a next cursor');
select is(
  jsonb_array_length(public.list_goal_proposal_history(
    '10000000-0000-0000-0000-000000000321', 4,
    (select result#>>'{data,next_cursor}' from first_proposals)
  )#>'{data,items}'),
  1,
  'proposal history cursor returns the remaining item'
);
select is(
  public.list_goal_proposal_history(
    '10000000-0000-0000-0000-000000000321', 4,
    (select result#>>'{data,next_cursor}' from first_proposals)
  )#>>'{data,items,0,target_value}',
  '11',
  'proposal history cursor uses the UUID tie-breaker at an equal timestamp'
);

select is(public.list_goal_history('10000000-0000-0000-0000-000000000321', 3, 'bad')#>>'{error,code}', 'INVALID_CURSOR', 'invalid cursor is rejected');
select is(
  public.list_goal_history(
    '10000000-0000-0000-0000-000000000321',
    3,
    encode(convert_to('2026-08-04 00:00:00+00|60000000-0000-0000-0000-000000000323|trailing', 'UTF8'), 'base64')
  )#>>'{error,code}',
  'INVALID_CURSOR',
  'cursor rejects trailing fields'
);
select is(public.list_goal_proposal_history('10000000-0000-0000-0000-000000000321', 31, null)#>>'{error,code}', 'INVALID_LIMIT', 'oversized history page is rejected');
select is(public.list_goal_history('10000000-0000-0000-0000-000000000322', 3, null)#>>'{error,code}', 'SPACE_ACCESS_DENIED', 'goal history is isolated by space');
select is(public.list_goal_proposal_history('10000000-0000-0000-0000-000000000322', 4, null)#>>'{error,code}', 'SPACE_ACCESS_DENIED', 'proposal history is isolated by space');
select is(jsonb_array_length(public.get_goals_snapshot('10000000-0000-0000-0000-000000000321')#>'{data,history}'), 3, 'legacy snapshot caps goal history at three');
select is(jsonb_array_length(public.get_goals_snapshot('10000000-0000-0000-0000-000000000321')#>'{data,proposal_history}'), 4, 'legacy snapshot caps proposal history at four');

reset role;
select ok(not has_function_privilege('anon', 'public.list_goal_history(uuid,integer,text)', 'EXECUTE'), 'anon cannot execute goal history RPC');

select * from finish();
rollback;
