import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';

const host = '127.0.0.1';
const port = '4173';
const baseUrl = `http://${host}:${port}`;

function runNode(modulePath, args) {
  return spawn(process.execPath, [modulePath, ...args], {
    cwd: process.cwd(),
    env: process.env,
    stdio: 'inherit',
  });
}

async function waitForServer(timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    try {
      const response = await fetch(baseUrl);
      if (response.ok) return;
    } catch {
      // The preview server is still starting.
    }
    await delay(250);
  }

  throw new Error(`Preview server did not become ready at ${baseUrl}`);
}

const preview = runNode('node_modules/vite/bin/vite.js', [
  'preview',
  '--host',
  host,
  '--port',
  port,
  '--strictPort',
]);

try {
  await waitForServer();
  const playwright = runNode('node_modules/@playwright/test/cli.js', ['test']);
  const exitCode = await new Promise((resolve, reject) => {
    playwright.once('error', reject);
    playwright.once('exit', (code) => resolve(code ?? 1));
  });
  process.exitCode = exitCode;
} finally {
  preview.kill();
}
