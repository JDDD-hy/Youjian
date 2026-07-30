import { copyFile } from 'node:fs/promises';

// GitHub Pages serves 404.html without changing the requested URL. Reusing
// Vite's built shell lets React Router handle project-scoped deep links.
await copyFile('dist/index.html', 'dist/404.html');
