import path from 'node:path';
import { pathToFileURL } from 'node:url';

const workerUrl = pathToFileURL(path.resolve('dist/server/index.js')).href;
const { default: worker } = await import(`${workerUrl}?t=${Date.now()}`);
const env = {
  ASSETS: {
    async fetch(request) {
      const pathname = new URL(request.url).pathname;
      if (pathname === '/index.html')
        return new Response('<!doctype html><title>友间</title>', {
          status: 200,
          headers: { 'Content-Type': 'text/html; charset=utf-8' },
        });
      return new Response('Not found', { status: 404 });
    },
  },
};

const navigation = await worker.fetch(
  new Request('https://youjian.example/space/test', {
    headers: { Accept: 'text/html' },
  }),
  env,
);
if (navigation.status !== 200 || !(await navigation.text()).includes('友间'))
  throw new Error('Sites worker did not serve the SPA navigation fallback.');
if (
  !navigation.headers
    .get('Content-Security-Policy')
    ?.includes("default-src 'self'")
)
  throw new Error('Sites worker did not attach the production CSP.');

const missingAsset = await worker.fetch(
  new Request('https://youjian.example/missing.js'),
  env,
);
if (missingAsset.status !== 404)
  throw new Error('Sites worker must not rewrite missing assets to HTML.');

console.log('Sites worker verification passed.');
