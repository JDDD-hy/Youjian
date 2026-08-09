import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';
import { loadEnv } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig(({ mode }) => {
  const configuredBase = loadEnv(mode, process.cwd(), '').VITE_BASE_PATH ?? '/';
  const base = `/${configuredBase.replace(/^\/+|\/+$/g, '')}/`.replace(
    /^\/\/$/,
    '/',
  );
  return {
    base,
    plugins: [
      react(),
      VitePWA({
        registerType: 'prompt',
        injectRegister: false,
        includeAssets: [
          'favicon.png',
          'pwa-192-v2.png',
          'pwa-512-v2.png',
          'pwa-maskable-512-v2.png',
        ],
        manifest: {
          name: '友间 · Youjian',
          short_name: '友间',
          description: '和固定好友共享专注状态与时间。',
          lang: 'zh-CN',
          start_url: base,
          scope: base,
          display: 'standalone',
          background_color: '#F7F3EA',
          theme_color: '#F7F3EA',
          icons: [
            {
              src: `${base}pwa-192-v2.png`,
              sizes: '192x192',
              type: 'image/png',
              purpose: 'any',
            },
            {
              src: `${base}pwa-512-v2.png`,
              sizes: '512x512',
              type: 'image/png',
              purpose: 'any',
            },
            {
              src: `${base}pwa-maskable-512-v2.png`,
              sizes: '512x512',
              type: 'image/png',
              purpose: 'maskable',
            },
          ],
        },
        workbox: {
          navigateFallback: `${base}index.html`,
          cleanupOutdatedCaches: true,
          runtimeCaching: [
            {
              urlPattern: ({ url }) =>
                ['/auth/v1', '/rest/v1', '/realtime/v1', '/functions/v1'].some(
                  (prefix) => url.pathname.startsWith(prefix),
                ),
              handler: 'NetworkOnly',
              method: 'GET',
            },
          ],
        },
        devOptions: { enabled: false },
      }),
    ],
    build: {
      sourcemap: false,
    },
    server: {
      host: '0.0.0.0',
      port: 5173,
    },
    test: {
      environment: 'jsdom',
      setupFiles: ['./src/test/setup.ts'],
      exclude: ['e2e/**', 'node_modules/**'],
      coverage: {
        reporter: ['text', 'html'],
      },
    },
  };
});

