import { expect, test } from '@playwright/test';

test('welcome page fits the viewport and exposes the primary action', async ({
  page,
}) => {
  await page.goto('/');

  await expect(page.getByRole('heading', { name: '友间' })).toBeVisible();
  await expect(page.getByRole('link', { name: '创建友间' })).toBeVisible();

  const configuredViewport = page.viewportSize()?.width;
  const layout = await page.evaluate((configuredWidth) => {
    const clientWidth = document.documentElement.clientWidth;
    const viewportWidth =
      configuredWidth ?? window.visualViewport?.width ?? clientWidth;
    return {
      clientWidth,
      viewportWidth,
      scrollWidth: document.documentElement.scrollWidth,
      offenders: Array.from(document.querySelectorAll<HTMLElement>('body *'))
        .map((element) => ({
          element: `${element.tagName.toLowerCase()}.${element.className}`,
          left: element.getBoundingClientRect().left,
          right: element.getBoundingClientRect().right,
        }))
        .filter(
          ({ left, right }) => left < -0.5 || right > viewportWidth + 0.5,
        ),
    };
  }, configuredViewport);
  expect(layout.offenders, JSON.stringify(layout)).toEqual([]);
  expect(layout.scrollWidth, JSON.stringify(layout)).toBeLessThanOrEqual(
    Math.ceil(layout.viewportWidth) + 1,
  );
});

test('welcome page remains usable at 200% text size', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => {
    document.documentElement.style.fontSize = '200%';
  });

  await expect(page.getByRole('heading', { name: '友间' })).toBeVisible();
  await expect(page.getByRole('link', { name: '创建友间' })).toBeVisible();
  const configuredViewport = page.viewportSize()?.width;
  const layout = await page.evaluate(
    (configuredWidth) => ({
      clientWidth: document.documentElement.clientWidth,
      viewportWidth:
        configuredWidth ??
        window.visualViewport?.width ??
        document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      offenders: Array.from(document.querySelectorAll<HTMLElement>('body *'))
        .map((element) => ({
          element: `${element.tagName.toLowerCase()}.${element.className}`,
          left: element.getBoundingClientRect().left,
          right: element.getBoundingClientRect().right,
        }))
        .filter(
          ({ left, right }) =>
            left < -0.5 ||
            right >
              (configuredWidth ??
                window.visualViewport?.width ??
                document.documentElement.clientWidth) +
                0.5,
        ),
    }),
    configuredViewport,
  );
  expect(layout.offenders, JSON.stringify(layout)).toEqual([]);
  expect(layout.scrollWidth, JSON.stringify(layout)).toBeLessThanOrEqual(
    Math.ceil(layout.viewportWidth) + 1,
  );
});

test('primary action stays reachable with a compact keyboard-height viewport', async ({
  page,
}) => {
  await page.setViewportSize({ width: 320, height: 360 });
  await page.goto('/');
  const create = page.getByRole('link', { name: '创建友间' });
  await create.scrollIntoViewIfNeeded();
  await expect(create).toBeVisible();
  await create.focus();
  await expect(create).toBeFocused();
});
