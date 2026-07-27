import { expect, test } from '@playwright/test';

test('welcome page fits the viewport and exposes the primary action', async ({
  page,
}) => {
  await page.goto('/');

  await expect(page.getByRole('heading', { name: '友间' })).toBeVisible();
  await expect(page.getByRole('link', { name: '创建友间' })).toBeVisible();

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);
});
