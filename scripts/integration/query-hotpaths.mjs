import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

// Only the local/CI container is addressed. Fixtures and schema changes roll back.
const migration = readFileSync(
  new URL(
    '../../supabase/migrations/20260727141300_0014_goal_lifecycle_observability.sql',
    import.meta.url,
  ),
  'utf8',
);
const original = migration.match(
  /create or replace function public\.run_goal_maintenance\([\s\S]*?end \$\$;/,
)?.[0];
assert.ok(original, 'Original goal maintenance definition is available');
const baseline = original.replace(
  'public.run_goal_maintenance(',
  'pg_temp.goal_maintenance_baseline(',
);
const output = execFileSync(
  'docker',
  [
    'exec',
    '-i',
    'supabase_db_youjian',
    'psql',
    '-X',
    '-qAt',
    '-v',
    'ON_ERROR_STOP=1',
    '-U',
    'postgres',
    '-d',
    'postgres',
  ],
  {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
    stdio: ['pipe', 'pipe', 'pipe'],
    input: `
begin;
set local statement_timeout='60s';
create temporary table samples(name text, before_ms numeric, after_ms numeric, detail jsonb);
${baseline}
create temporary table fixture_users as select gen_random_uuid() id from generate_series(1,63);
insert into auth.users(id) select id from fixture_users;
insert into public.profiles(id,timezone) select id,'UTC' from fixture_users;
insert into public.spaces(id,name,owner_id,timezone,invite_token_hash)
select id,'Query benchmark',id,'UTC','query-benchmark-'||id from fixture_users;
insert into public.space_members(space_id,user_id,display_name,role)
select id,id,'Benchmark owner','owner' from fixture_users;
insert into private.maintenance_runs(job_name,started_at,finished_at,status,source,result)
select 'query-benchmark',now()-g*interval '1 minute',now()-g*interval '1 minute','succeeded','cron','{}'
from generate_series(1,43201) g;
analyze private.maintenance_runs;
analyze public.space_members;

do $bench$
declare started timestamptz; before_ms numeric; after_ms numeric; before_plan jsonb; after_plan jsonb;
begin
  perform public.validate_iana_timezone('Europe/Paris');
  perform exists(select 1 from pg_catalog.pg_timezone_names where name='Europe/Paris');
  started:=clock_timestamp();
  for i in 1..5 loop
    perform exists(select 1 from pg_catalog.pg_timezone_names where name='Europe/Paris');
  end loop;
  before_ms:=extract(epoch from clock_timestamp()-started)*1000/5;
  started:=clock_timestamp();
  for i in 1..100 loop perform public.validate_iana_timezone('Europe/Paris'); end loop;
  after_ms:=extract(epoch from clock_timestamp()-started)*1000/100;
  insert into samples values('timezone_validation',before_ms,after_ms,'{}');

  -- Warm both paths so the comparison measures repeated scheduled work.
  perform pg_temp.goal_maintenance_baseline(now());
  perform public.run_goal_maintenance_before_missed_goal_fix(now());
  started:=clock_timestamp();
  for i in 1..5 loop perform pg_temp.goal_maintenance_baseline(now()); end loop;
  before_ms:=extract(epoch from clock_timestamp()-started)*1000/5;
  started:=clock_timestamp();
  for i in 1..5 loop perform public.run_goal_maintenance_before_missed_goal_fix(now()); end loop;
  after_ms:=extract(epoch from clock_timestamp()-started)*1000/5;
  insert into samples values('goal_maintenance',before_ms,after_ms,jsonb_build_object('extra_solo_rooms',63));

  drop index private.maintenance_runs_started_at;
  execute 'explain (analyze,buffers,format json) select id from private.maintenance_runs where started_at<now()-interval ''30 days'''
    into before_plan;
  create index maintenance_runs_started_at on private.maintenance_runs(started_at,id);
  execute 'explain (analyze,buffers,format json) select id from private.maintenance_runs where started_at<now()-interval ''30 days'''
    into after_plan;
  insert into samples values('maintenance_retention',
    (before_plan#>>'{0,Execution Time}')::numeric,
    (after_plan#>>'{0,Execution Time}')::numeric,
    jsonb_build_object('before_plan',before_plan->0->'Plan','after_plan',after_plan->0->'Plan'));
end $bench$;
select jsonb_object_agg(name,jsonb_build_object('before_ms',round(before_ms,4),'after_ms',round(after_ms,4),'detail',detail)) from samples;
rollback;
`,
  },
).trim();
const result = JSON.parse(output);
assert.ok(
  result.timezone_validation.after_ms < result.timezone_validation.before_ms,
  'Cached timezone validation is faster than rebuilding the catalog',
);
assert.ok(
  result.goal_maintenance.after_ms < result.goal_maintenance.before_ms,
  'Goal maintenance avoids redundant checks for solo rooms',
);
assert.match(
  JSON.stringify(result.maintenance_retention.detail.after_plan),
  /maintenance_runs_started_at/,
  'Retention query uses the new time index',
);
for (const [name, sample] of Object.entries(result)) {
  process.stdout.write(
    `${JSON.stringify({
      name,
      before_ms: sample.before_ms,
      after_ms: sample.after_ms,
      reduction_percent: Number(
        ((1 - sample.after_ms / sample.before_ms) * 100).toFixed(1),
      ),
    })}\n`,
  );
}
