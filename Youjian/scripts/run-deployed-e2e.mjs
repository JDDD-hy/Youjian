import { spawn } from 'node:child_process';

const baseUrl = process.env.PLAYWRIGHT_BASE_URL;
if (!baseUrl || !/^https:\/\//.test(baseUrl)) {
  console.error('PLAYWRIGHT_BASE_URL must be an HTTPS deployment URL.');
  process.exit(2);
}

const response = await fetch(baseUrl, { redirect: 'follow' });
if (!response.ok) {
  console.error(`Deployment returned HTTP ${response.status}.`);
  process.exit(2);
}

const child = spawn(
  process.execPath,
  [
    'node_modules/@playwright/test/cli.js',
    'test',
    'e2e/two-device-flow.spec.ts',
    'e2e/invite-settings.spec.ts',
    'e2e/deployed-timing.spec.ts',
    '--project=desktop-chromium',
  ],
  {
    cwd: process.cwd(),
    env: { ...process.env, E2E_EXPECT_CAPTCHA: '0' },
    stdio: 'inherit',
  },
);

const exitCode = await new Promise((resolve, reject) => {
  child.once('error', reject);
  child.once('exit', (code) => resolve(code ?? 1));
});
process.exitCode = exitCode;
