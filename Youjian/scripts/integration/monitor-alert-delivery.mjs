import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { createServer } from 'node:http';

function setCronActive(active) {
  execFileSync(
    'docker',
    [
      'exec',
      'supabase_db_youjian',
      'psql',
      '-v',
      'ON_ERROR_STOP=1',
      '-U',
      'supabase_admin',
      '-d',
      'postgres',
      '-Atqc',
      `update cron.job set active=${active ? 'true' : 'false'} where jobname='youjian-minute-maintenance'`,
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );
}

let resolvePayload;
const payloadReceived = new Promise((resolve) => {
  resolvePayload = resolve;
});
const server = createServer((request, response) => {
  const chunks = [];
  request.on('data', (chunk) => chunks.push(chunk));
  request.on('end', () => {
    response.writeHead(204).end();
    resolvePayload(JSON.parse(Buffer.concat(chunks).toString('utf8')));
  });
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const address = server.address();
assert.ok(address && typeof address === 'object');

try {
  setCronActive(false);
  const monitor = spawn(process.execPath, ['scripts/monitor-health.mjs'], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      YOUJIAN_ALERT_WEBHOOK_URL: `http://127.0.0.1:${address.port}/alerts`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const exitCode = await new Promise((resolve, reject) => {
    monitor.once('error', reject);
    monitor.once('exit', resolve);
  });
  assert.notEqual(
    exitCode,
    0,
    'An inactive Cron job must fail the health check.',
  );
  const payload = await Promise.race([
    payloadReceived,
    new Promise((_, reject) =>
      setTimeout(
        () => reject(new Error('Alert webhook was not called.')),
        5_000,
      ),
    ),
  ]);
  assert.equal(payload.service, 'youjian');
  assert.ok(payload.alerts.includes('CRON_JOB_MISSING_OR_INACTIVE'));
  process.stdout.write('Monitor alert delivery drill passed.\n');
} finally {
  setCronActive(true);
  await new Promise((resolve) => server.close(resolve));
}
