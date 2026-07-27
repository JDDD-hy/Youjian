import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: 'html',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    channel: process.env.CI ? undefined : 'chrome',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'mobile-320',
      use: {
        browserName: 'chromium',
        viewport: { width: 320, height: 800 },
        deviceScaleFactor: 2,
        hasTouch: true,
        isMobile: true,
      },
    },
    { name: 'desktop-chrome', use: { ...devices['Desktop Chrome'] } },
  ],
});
