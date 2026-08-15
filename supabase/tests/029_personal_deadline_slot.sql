begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000291'),
  ('00000000-0000-0000-0000-000000000292');
insert into public.profiles(id,timezone) values
  ('00000000-0000-0000-0000-000000000291','UTC'),
  ('00000000-0000-0000-0000-000000000292','UTC');

select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid='public.personal_deadlines'::regclass),
  'personal deadline table has RLS enabled'
);
select ok(
  not has_table_privilege('authenticated','public.personal_deadlines','select'),
  'authenticated clients cannot select the deadline table directly'
);
select ok(
  not has_table_privilege('authenticated','public.personal_deadlines','insert'),
  'authenticated clients cannot insert into the deadline table directly'
);
select ok(
  not has_table_privilege('authenticated','public.personal_deadlines','update'),
  'authenticated clients cannot update the deadline table directly'
);
select ok(
  not has_function_privilege('anon','public.get_personal_deadline()','execute'),
  'anonymous clients cannot read a personal deadline'
);
select ok(
  not has_function_privilege('anon','public.set_personal_deadline(text,date,text)','execute'),
  'anonymous clients cannot set a personal deadline'
);
select ok(
  has_function_privilege('authenticated','public.get_personal_deadline()','execute'),
  'authenticated clients may read their deadline through the RPC'
);
select ok(
  has_function_privilege('authenticated','public.set_personal_deadline(text,date,text)','execute'),
  'authenticated clients may set their deadline through the RPC'
);

set local role authenticated;
select is(
  public.get_personal_deadline()#>>'{error,code}',
  'AUTH_REQUIRED',
  'an authenticated database role without a principal is rejected'
);

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000291',true);
select is(
  public.get_personal_deadline()#>'{data,deadline}',
  'null'::jsonb,
  'a new principal has one empty deadline slot'
);
select is(
  public.set_personal_deadline('   ',current_date,'UTC')#>>'{error,code}',
  'INVALID_DEADLINE_TITLE',
  'a blank title is rejected'
);
select is(
  public.set_personal_deadline(repeat('期',41),current_date,'UTC')#>>'{error,code}',
  'INVALID_DEADLINE_TITLE',
  'a title longer than forty Unicode characters is rejected'
);
select is(
  public.set_personal_deadline('法考',current_date,'Not/A_Timezone')#>>'{error,code}',
  'INVALID_TIMEZONE',
  'an unknown device timezone is rejected'
);
select is(
  public.set_personal_deadline(
    '法考',
    (pg_catalog.clock_timestamp() at time zone 'America/New_York')::date-1,
    'America/New_York'
  )#>>'{error,code}',
  'INVALID_DEADLINE_DATE',
  'a date before today in the supplied device timezone is rejected'
);
select is(
  public.set_personal_deadline(
    '  距离法考  ',
    (pg_catalog.clock_timestamp() at time zone 'America/New_York')::date,
    'America/New_York'
  )#>>'{data,deadline,title}',
  '距离法考',
  'today is allowed and the title is trimmed'
);
select is(
  public.get_personal_deadline()#>>'{data,deadline,target_date}',
  (pg_catalog.clock_timestamp() at time zone 'America/New_York')::date::text,
  'the independent read RPC returns the saved date'
);
select ok(
  (public.get_personal_deadline()#>>'{data,deadline,id}')::uuid is not null,
  'the deadline response exposes its id'
);
select ok(
  (public.get_personal_deadline()#>>'{data,deadline,created_at}')::timestamptz is not null
  and (public.get_personal_deadline()#>>'{data,deadline,updated_at}')::timestamptz is not null,
  'the deadline response exposes both timestamps'
);

select set_config('deadline.first_id',public.get_personal_deadline()#>>'{data,deadline,id}',true);
select is(
  public.set_personal_deadline('毕业答辩',current_date+30,'UTC')#>>'{data,deadline,title}',
  '毕业答辩',
  'setting a new deadline overwrites the single slot'
);
select is(
  public.get_personal_deadline()#>>'{data,deadline,id}',
  current_setting('deadline.first_id'),
  'upsert preserves the slot identity'
);
reset role;
select is(
  (select count(*) from public.personal_deadlines where user_id='00000000-0000-0000-0000-000000000291'),
  1::bigint,
  'upsert leaves exactly one row for the principal'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000292',true);
select is(
  public.get_personal_deadline()#>'{data,deadline}',
  'null'::jsonb,
  'another principal cannot read the first principal deadline'
);
select is(
  public.set_personal_deadline('我的考试',current_date+7,'UTC')#>>'{data,deadline,title}',
  '我的考试',
  'another principal can fill their own slot'
);
select is(
  public.get_personal_deadline()#>>'{data,deadline,title}',
  '我的考试',
  'the second principal reads only their own deadline'
);
select throws_ok(
  $$select * from public.personal_deadlines$$,
  '42501',null,
  'authenticated clients cannot bypass the RPC to inspect other rows'
);
reset role;

select is(
  (select count(*) from public.personal_deadlines),
  2::bigint,
  'one independent slot is stored per principal'
);

select * from finish();
rollback;
