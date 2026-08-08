import { promises as fs } from 'node:fs';
import { chromium } from '@playwright/test';

const logo = await fs.readFile('public/logo.png');
const logoDataUrl = `data:image/png;base64,${logo.toString('base64')}`;

const browser = await chromium.launch({
  channel: process.env.CI ? undefined : 'chrome',
});

try {
  const variants = [
    { path: 'public/favicon.png', size: 64, padding: 0, background: 'transparent' },
    { path: 'public/youjian-logo.png', size: 512, padding: 0, background: 'transparent' },
    { path: 'public/pwa-192-v2.png', size: 192, padding: 8, background: 'transparent' },
    { path: 'public/pwa-512-v2.png', size: 512, padding: 20, background: 'transparent' },
    { path: 'public/pwa-maskable-512-v2.png', size: 512, padding: 40, background: '#F7F3EA' },
  ];

  for (const { path, size, padding, background } of variants) {
    const page = await browser.newPage({
      viewport: { width: size, height: size },
    });
    await page.setContent(
      `<style>
        * { box-sizing: border-box; }
        html, body { margin: 0; width: 100%; height: 100%; background: ${background}; }
        img { display: block; width: 100%; height: 100%; padding: ${padding}px; object-fit: contain; }
      </style><img src="${logoDataUrl}" />`,
    );
    await page.locator('img').waitFor({ state: 'visible' });
    await page.screenshot({
      path,
      omitBackground: background === 'transparent',
    });
    await page.close();
  }
} finally {
  await browser.close();
}
