import { defineConfig, devices } from '@playwright/test';

const chromiumChannel =
  process.env.PLAYWRIGHT_CHANNEL ?? (process.env.CI ? undefined : 'chrome');

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: 'html',
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:4173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'mobile-320',
      use: {
        browserName: 'chromium',
        channel: chromiumChannel,
        viewport: { width: 320, height: 800 },
        deviceScaleFactor: 2,
        hasTouch: true,
        isMobile: true,
      },
    },
    {
      name: 'desktop-chromium',
      use: { ...devices['Desktop Chrome'], channel: chromiumChannel },
    },
    {
      name: 'android-chromium',
      use: { ...devices['Pixel 7'], channel: chromiumChannel },
    },
    {
      name: 'iphone-webkit',
      use: { ...devices['iPhone 13'], deviceScaleFactor: 1 },
    },
  ],
});
