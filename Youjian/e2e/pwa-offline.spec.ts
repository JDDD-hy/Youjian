import { expect, test, type Page } from '@playwright/test';

async function prepareServiceWorker(page: Page) {
  await page.goto('./');
  await page.evaluate(async () => {
    await navigator.serviceWorker.ready;
  });
  await page.reload();
  await expect
    .poll(() =>
      page.evaluate(() => Boolean(navigator.serviceWorker.controller)),
    )
    .toBe(true);
}

test('service worker registers, activates, and controls the page', async ({
  page,
}) => {
  await prepareServiceWorker(page);
  expect(
    await page.evaluate(async () =>
      Boolean((await navigator.serviceWorker.getRegistration())?.active),
    ),
  ).toBe(true);
});

test('offline shell is cached while API requests stay network-only', async ({
  browserName,
  context,
  page,
}) => {
  test.skip(
    browserName === 'webkit',
    'Playwright WebKit on Windows cannot emulate offline service-worker fetches.',
  );
  await prepareServiceWorker(page);

  const cachedShell = await page.evaluate(async () => {
    const shellPath = new URL('./index.html', window.location.href).pathname;
    const keys = await caches.keys();
    const matches = await Promise.all(
      keys.map(async (key) =>
        Boolean(
          await (
            await caches.open(key)
          ).match(shellPath, {
            ignoreSearch: true,
          }),
        ),
      ),
    );
    return matches.some(Boolean);
  });
  expect(cachedShell).toBe(true);

  await context.setOffline(true);
  try {
    const result = await page.evaluate(async () => {
      const shell = await fetch('./index.html').then((response) => response.ok);
      const apiFailed = await fetch('/rest/v1/offline-probe').then(
        () => false,
        () => true,
      );
      return { shell, apiFailed };
    });
    expect(result).toEqual({ shell: true, apiFailed: true });
  } finally {
    await context.setOffline(false);
  }
});
