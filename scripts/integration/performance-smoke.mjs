import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
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

const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
  global: { headers: { 'x-client-info': 'youjian-performance-smoke' } },
});
const { error: authError } = await supabase.auth.signInAnonymously({
  options: { captchaToken: 'XXXX.DUMMY.TOKEN.XXXX' },
});
assert.ifError(authError);
const { data: created, error: createError } = await supabase.rpc(
  'create_space',
  {
    p_display_name: 'perf-owner',
    p_space_name: `perf-${randomUUID().slice(0, 8)}`,
    p_space_timezone: 'Asia/Shanghai',
    p_profile_timezone: 'Asia/Shanghai',
    p_member_limit: 4,
    p_idempotency_key: randomUUID(),
  },
);
assert.ifError(createError);
assert.equal(created?.ok, true, 'Performance fixture creation failed');

const spaceId = created.data.space.id;
const samples = [];
for (let index = 0; index < 40; index += 1) {
  const started = performance.now();
  const { data, error } = await supabase.rpc('get_home_snapshot', {
    p_space_id: spaceId,
  });
  samples.push(performance.now() - started);
  assert.ifError(error);
  assert.equal(data?.ok, true, 'Snapshot benchmark returned an error envelope');
}
samples.sort((left, right) => left - right);
const p50 = samples[Math.ceil(samples.length * 0.5) - 1];
const p95 = samples[Math.ceil(samples.length * 0.95) - 1];
const result = {
  samples: samples.length,
  p50_ms: Number(p50.toFixed(1)),
  p95_ms: Number(p95.toFixed(1)),
  budget_ms: 300,
};
process.stdout.write(`${JSON.stringify(result)}\n`);
assert.ok(
  p95 < result.budget_ms,
  `get_home_snapshot p95 ${p95.toFixed(1)} ms exceeded ${result.budget_ms} ms`,
);
