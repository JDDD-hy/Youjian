import { copyFile, mkdir } from 'node:fs/promises';

// GitHub Pages serves 404.html without changing the requested URL. Reusing
// Vite's built shell lets React Router handle project-scoped deep links.
await copyFile('dist/index.html', 'dist/404.html');

// Sites runs this worker in front of the static assets so direct SPA routes,
// including invite links, receive the application shell instead of a 404.
await mkdir('dist/server', { recursive: true });
await copyFile('sites/worker.js', 'dist/server/index.js');
