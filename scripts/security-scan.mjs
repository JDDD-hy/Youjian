import { promises as fs } from 'node:fs';
import path from 'node:path';

const roots = [
  'src',
  'public',
  'supabase/migrations',
  'scripts',
  '.github',
  '../.github/workflows/youjian-ci.yml',
  '.env.example',
  'index.html',
  'vite.config.ts',
  'package.json',
];
const textExtensions = new Set([
  '.ts',
  '.tsx',
  '.js',
  '.mjs',
  '.sql',
  '.yml',
  '.yaml',
  '.json',
  '.html',
  '.txt',
  '',
]);
const forbidden = [
  { label: 'Supabase secret key', pattern: /sb_secret_[A-Za-z0-9_-]{12,}/g },
  {
    label: 'populated service role key',
    pattern: /(?:SERVICE_ROLE_KEY|service_role_key)\s*=\s*[^\s#]+/g,
  },
  {
    label: 'database password URL',
    pattern: /postgres(?:ql)?:\/\/[^:\s]+:[^@\s]+@/g,
  },
  {
    label: 'private key',
    pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g,
  },
];

async function collect(target) {
  const stat = await fs.stat(target);
  if (stat.isFile()) return [target];
  const entries = await fs.readdir(target, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => collect(path.join(target, entry.name))),
  );
  return nested.flat();
}

const existingRoots = [];
for (const root of roots) {
  try {
    await fs.access(root);
    existingRoots.push(root);
  } catch {
    // Optional directory is not present yet.
  }
}

const files = (await Promise.all(existingRoots.map(collect)))
  .flat()
  .filter((file) => textExtensions.has(path.extname(file)));
const failures = [];

for (const file of files) {
  const content = await fs.readFile(file, 'utf8');
  for (const rule of forbidden) {
    if (rule.pattern.test(content)) failures.push(`${rule.label}: ${file}`);
    rule.pattern.lastIndex = 0;
  }
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Security scan passed for ${files.length} source files.`);
}
