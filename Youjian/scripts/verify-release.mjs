import { promises as fs } from 'node:fs';
import path from 'node:path';
import { gzipSync } from 'node:zlib';

const required = [
  'dist/index.html',
  'dist/404.html',
  'dist/manifest.webmanifest',
  'dist/sw.js',
  'dist/pwa-icon.svg',
  'dist/pwa-192.png',
  'dist/pwa-512.png',
  'dist/_headers',
];
const errors = [];

for (const file of required) {
  try {
    await fs.access(file);
  } catch {
    errors.push(`Missing release artifact: ${file}`);
  }
}

try {
  const manifest = JSON.parse(
    await fs.readFile('dist/manifest.webmanifest', 'utf8'),
  );
  if (manifest.display !== 'standalone') {
    errors.push('PWA display mode must be standalone.');
  }
  const iconSizes = new Set(manifest.icons?.map((icon) => icon.sizes));
  if (!iconSizes.has('192x192') || !iconSizes.has('512x512')) {
    errors.push('PWA manifest must include 192x192 and 512x512 icons.');
  }
} catch {
  errors.push('Unable to parse PWA manifest.');
}

try {
  const headers = await fs.readFile('dist/_headers', 'utf8');
  for (const directive of [
    "default-src 'self'",
    "script-src 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
  ]) {
    if (!headers.includes(directive)) {
      errors.push(`Missing CSP directive: ${directive}`);
    }
  }
  if (/127\.0\.0\.1|localhost/.test(headers)) {
    errors.push('Production security headers must not allow loopback origins.');
  }
} catch {
  // Missing headers are already reported above.
}

try {
  const html = await fs.readFile('dist/index.html', 'utf8');
  if (!html.includes('http-equiv="Content-Security-Policy"')) {
    errors.push(
      'Production HTML must include a CSP meta policy for static hosts.',
    );
  }
  if (/127\.0\.0\.1|localhost|%VITE_CSP_CONNECT_SRC%/.test(html)) {
    errors.push(
      'Production HTML CSP contains a loopback or unresolved connection source.',
    );
  }
} catch {
  // Missing HTML is already reported above.
}

let largestGzip = 0;
let largestAsset = '';
try {
  const assets = await fs.readdir('dist/assets');
  for (const asset of assets.filter((name) => name.endsWith('.js'))) {
    const contents = await fs.readFile(path.join('dist/assets', asset));
    const size = gzipSync(contents).byteLength;
    if (size > largestGzip) {
      largestGzip = size;
      largestAsset = asset;
    }
  }
} catch {
  errors.push('Unable to inspect dist/assets.');
}

if (largestGzip > 200 * 1024) {
  errors.push(
    `JavaScript budget exceeded: ${largestAsset} is ${largestGzip} bytes gzip.`,
  );
}

const sourceMaps = [];
async function findMaps(directory) {
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) await findMaps(target);
    else if (entry.name.endsWith('.map')) sourceMaps.push(target);
  }
}
try {
  await findMaps('dist');
} catch {
  // Missing dist is already reported above.
}
if (sourceMaps.length)
  errors.push(`Public source maps found: ${sourceMaps.join(', ')}`);

if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
} else {
  console.log(
    `Release verification passed. Largest JS gzip: ${largestGzip} bytes.`,
  );
}
