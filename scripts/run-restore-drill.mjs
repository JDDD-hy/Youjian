import { spawnSync } from 'node:child_process';

const shell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
const result = spawnSync(
  shell,
  [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    'scripts/restore-drill.ps1',
  ],
  { stdio: 'inherit' },
);

if (result.error) {
  process.stderr.write(
    `Unable to start ${shell} for the restore drill: ${result.error.message}\n`,
  );
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
