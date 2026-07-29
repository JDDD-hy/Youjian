import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const workspace = fileURLToPath(new URL('..', import.meta.url));
const auditCommand =
  process.platform === 'win32'
    ? [
        process.env.ComSpec ?? 'cmd.exe',
        ['/d', '/s', '/c', 'npm audit --omit=dev --json'],
      ]
    : ['npm', ['audit', '--omit=dev', '--json']];
const result = spawnSync(auditCommand[0], auditCommand[1], {
  cwd: workspace,
  encoding: 'utf8',
});
assert.ok(result.stdout, result.stderr || 'npm audit did not return JSON.');
const report = JSON.parse(result.stdout);
const vulnerabilities = Object.values(report.vulnerabilities ?? {});

if (vulnerabilities.length === 0) {
  process.stdout.write(
    'Production dependency audit passed with no findings.\n',
  );
  process.exit(0);
}

// GHSA-qwww-vcr4-c8h2 affects only unstable React Server Components APIs.
// React Router has published 8.3.0 as the patched version, but that version is
// not available from npm yet. This Vite SPA does not install React Router's
// RSC tooling or reference any unstable RSC API. Keep the exception narrow and
// time-bounded so every other advisory, package, or future date fails CI.
const exception = {
  advisorySource: 1124282,
  expiresAt: '2026-08-15T00:00:00Z',
  packages: new Set(['react-router', 'react-router-dom']),
};
assert.ok(
  Date.now() < Date.parse(exception.expiresAt),
  'The temporary React Router RSC advisory exception has expired.',
);

const packageJson = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
);
assert.equal(
  packageJson.dependencies?.['@react-router/dev'],
  undefined,
  'RSC tooling is installed, so the advisory exception is invalid.',
);
function sourcePaths(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return sourcePaths(path);
    return /\.tsx?$/.test(entry.name) ? [path] : [];
  });
}
const rscSources = sourcePaths(join(workspace, 'src')).filter((path) =>
  /unstable_|createCallServer|\bRSC\b/.test(readFileSync(path, 'utf8')),
);
assert.deepEqual(
  rscSources,
  [],
  `RSC-related application code invalidates the advisory exception:\n${rscSources.join('\n')}`,
);

for (const vulnerability of vulnerabilities) {
  assert.ok(
    exception.packages.has(vulnerability.name),
    `Unapproved production vulnerability: ${vulnerability.name}`,
  );
  const advisories = vulnerability.via.filter(
    (item) => typeof item === 'object',
  );
  const indirectPackages = vulnerability.via.filter(
    (item) => typeof item === 'string',
  );
  assert.ok(
    advisories.every((item) => item.source === exception.advisorySource),
    `Unapproved advisory affects ${vulnerability.name}.`,
  );
  assert.ok(
    indirectPackages.every((name) => exception.packages.has(name)),
    `Unapproved transitive vulnerability affects ${vulnerability.name}.`,
  );
}

process.stdout.write(
  `Production dependency audit passed with one non-applicable RSC-only exception expiring ${exception.expiresAt}.\n`,
);
