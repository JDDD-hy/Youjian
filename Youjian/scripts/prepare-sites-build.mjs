import { copyFile, cp, mkdir, readdir, rm } from 'node:fs/promises';
import path from 'node:path';

const dist = path.resolve('dist');
const client = path.join(dist, 'client');
const server = path.join(dist, 'server');
const ignored = new Set(['client', 'server', '.openai']);

await rm(client, { recursive: true, force: true });
await rm(server, { recursive: true, force: true });
await mkdir(client, { recursive: true });
await mkdir(server, { recursive: true });
await copyFile(path.join(dist, 'index.html'), path.join(dist, '404.html'));

for (const entry of await readdir(dist, { withFileTypes: true })) {
  if (ignored.has(entry.name)) continue;
  await cp(path.join(dist, entry.name), path.join(client, entry.name), {
    recursive: true,
  });
}

await cp(path.resolve('sites/worker.js'), path.join(server, 'index.js'));
console.log('Prepared Cloudflare Workers-compatible Sites output.');
