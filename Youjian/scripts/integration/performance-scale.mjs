import assert from 'node:assert/strict';
import { execFileSync, execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { createClient } from '@supabase/supabase-js';

const status = new Map(
  execSync('npx supabase status -o env', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  })
    .split(/\r?\n/)
    .map((line) => line.match(/^([A-Z_]+)="(.*)"$/))
    .filter(Boolean)
    .map((match) => [match[1], match[2]]),
);
const url = status.get('API_URL');
const anonKey = status.get('ANON_KEY');
assert.ok(url && anonKey, 'Local Supabase is not running');

function sql(statement) {
  return execFileSync(
    'docker',
    [
      'exec',
      'supabase_db_youjian',
      'psql',
      '-v',
      'ON_ERROR_STOP=1',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-Atqc',
      statement,
    ],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  ).trim();
}

function uuid(value, label) {
  assert.match(value, /^[0-9a-f]{8}-[0-9a-f-]{27}$/i, label);
  return value;
}

// Repeated local runs keep one representative scale fixture instead of
// multiplying synthetic rooms indefinitely. Only the exact marker pair owned
// by this script is eligible for cleanup.
sql(`
  set session_replication_role='replica';
  create temporary table old_scale_spaces on commit drop as
  select distinct sp.id,sp.owner_id
  from public.spaces sp
  join public.space_members m on m.space_id=sp.id and m.role='owner'
  where sp.name like 'scale-%' and m.display_name='scale-owner';
  delete from public.focus_connection_intervals where session_id in(select id from public.focus_sessions where space_id in(select id from old_scale_spaces));
  delete from public.focus_events where session_id in(select id from public.focus_sessions where space_id in(select id from old_scale_spaces));
  delete from public.focus_commands where session_id in(select id from public.focus_sessions where space_id in(select id from old_scale_spaces));
  delete from public.focus_segments where session_id in(select id from public.focus_sessions where space_id in(select id from old_scale_spaces));
  delete from public.focus_sessions where space_id in(select id from old_scale_spaces);
  delete from public.space_members where space_id in(select id from old_scale_spaces);
  delete from public.spaces where id in(select id from old_scale_spaces);
  delete from public.profiles where id in(select owner_id from old_scale_spaces) and not exists(select 1 from public.space_members where user_id=profiles.id);
  delete from auth.users where id in(select owner_id from old_scale_spaces) and not exists(select 1 from public.space_members where user_id=users.id);
  set session_replication_role='origin';
`);

async function benchmark(name, runs, operation) {
  for (let index = 0; index < 3; index += 1) await operation();
  const samples = [];
  for (let index = 0; index < runs; index += 1) {
    const started = performance.now();
    const { data, error } = await operation();
    samples.push(performance.now() - started);
    assert.ifError(error);
    assert.equal(data?.ok, true, `${name} returned an error envelope`);
  }
  samples.sort((left, right) => left - right);
  const percentile = (ratio) => samples[Math.ceil(samples.length * ratio) - 1];
  return {
    samples: samples.length,
    p50_ms: Number(percentile(0.5).toFixed(1)),
    p95_ms: Number(percentile(0.95).toFixed(1)),
  };
}

const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
  global: { headers: { 'x-client-info': 'youjian-scale-performance' } },
});
const { data: auth, error: authError } = await supabase.auth.signInAnonymously({
  options: { captchaToken: 'XXXX.DUMMY.TOKEN.XXXX' },
});
assert.ifError(authError);
const userId = uuid(auth.user?.id, 'Anonymous fixture user is missing');
const { data: created, error: createError } = await supabase.rpc(
  'create_space',
  {
    p_display_name: 'scale-owner',
    p_space_name: `scale-${randomUUID().slice(0, 8)}`,
    p_space_timezone: 'Asia/Shanghai',
    p_profile_timezone: 'Asia/Shanghai',
    p_member_limit: 12,
    p_idempotency_key: randomUUID(),
  },
);
assert.ifError(createError);
assert.equal(created?.ok, true, 'Scale fixture room creation failed');
const spaceId = uuid(created.data.space.id, 'Scale fixture space is missing');
const memberId = uuid(
  created.data.membership.member_id,
  'Scale fixture membership is missing',
);

sql(`
  insert into public.focus_sessions(
    id,space_id,user_id,member_id,task_name,category,status,
    accumulated_focus_seconds,started_at,completed_at,completion_reason,last_seen_at,created_at
  )
  select gen_random_uuid(),'${spaceId}'::uuid,'${userId}'::uuid,'${memberId}'::uuid,
    'Synthetic scale fixture','study','completed',3600,
    now()-((g%365)+1)*interval '1 day'-interval '1 hour',
    now()-((g%365)+1)*interval '1 day','manual_end',
    now()-((g%365)+1)*interval '1 day',now()
  from generate_series(1,10000) g;

  insert into public.focus_segments(session_id,started_at,ended_at)
  select s.id,s.started_at+part*interval '30 minutes',s.started_at+(part+1)*interval '30 minutes'
  from public.focus_sessions s cross join generate_series(0,1) part
  where s.space_id='${spaceId}'::uuid and s.task_name='Synthetic scale fixture';

  analyze public.focus_sessions;
  analyze public.focus_segments;
`);

const counts = sql(`
  select count(distinct s.id) filter(where s.task_name='Synthetic scale fixture'),count(g.id)
  from public.focus_sessions s left join public.focus_segments g on g.session_id=s.id
  where s.space_id='${spaceId}'::uuid;
`);
assert.equal(
  counts,
  '10000|20000',
  'Expected 10,000 sessions and 20,000 segments',
);

const today = new Date().toISOString().slice(0, 10);
const rangeNow = Date.now();
const periodStart = new Date(rangeNow - 365 * 86400000).toISOString();
const periodEnd = new Date(rangeNow).toISOString();
const results = {
  fixture: { sessions: 10000, segments: 20000 },
  home: await benchmark('get_home_snapshot', 30, () =>
    supabase.rpc('get_home_snapshot', { p_space_id: spaceId }),
  ),
  monthly_stats: await benchmark('get_stats_summary', 30, () =>
    supabase.rpc('get_stats_summary', {
      p_space_id: spaceId,
      p_view: 'mine',
      p_period: 'monthly',
      p_anchor_local_date: today,
    }),
  ),
  history_page: await benchmark('list_focus_history', 30, () =>
    supabase.rpc('list_focus_history', {
      p_space_id: spaceId,
      p_view: 'mine',
      p_period_start: periodStart,
      p_period_end: periodEnd,
      p_limit: 100,
      p_cursor: null,
    }),
  ),
  budget_ms: 300,
};

for (const [name, result] of Object.entries(results)) {
  if (name === 'fixture' || name === 'budget_ms') continue;
  assert.ok(
    result.p95_ms < results.budget_ms,
    `${name} p95 ${result.p95_ms} ms exceeded ${results.budget_ms} ms`,
  );
}
process.stdout.write(`${JSON.stringify(results)}\n`);
