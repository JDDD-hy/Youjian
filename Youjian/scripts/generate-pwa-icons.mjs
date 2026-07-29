import { promises as fs } from 'node:fs';
import { chromium } from '@playwright/test';

const svg = await fs.readFile('public/pwa-icon.svg', 'utf8');
const browser = await chromium.launch({
  channel: process.env.CI ? undefined : 'chrome',
});

try {
  for (const size of [192, 512]) {
    const page = await browser.newPage({
      viewport: { width: size, height: size },
    });
    await page.setContent(
      `<style>*{margin:0}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`,
    );
    await page.screenshot({
      path: `public/pwa-${size}.png`,
      omitBackground: false,
    });
    await page.close();
  }
} finally {
  await browser.close();
}
