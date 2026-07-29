import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

test('Turnstile validates anonymous auth before creating a room', async ({
  page,
}) => {
  const suffix = randomUUID().slice(0, 8);
  const spaceName = `验证友间-${suffix}`;
  await page.goto('/create');
  await expect(page.locator('[name="cf-turnstile-response"]')).toHaveValue(
    /.+/,
    { timeout: 30_000 },
  );
  await page.getByLabel('你的昵称').fill(`成员-${suffix}`);
  await page.getByLabel('友间名称').fill(spaceName);
  await page.getByRole('checkbox').check();
  const layout = await page.evaluate(() => {
    const captcha = document.querySelector<HTMLElement>('.captcha-field');
    const button = Array.from(document.querySelectorAll('button')).find(
      (item) => item.textContent?.trim() === '创建友间',
    );
    return {
      captchaBottom: captcha?.getBoundingClientRect().bottom ?? Infinity,
      buttonTop: button?.getBoundingClientRect().top ?? -Infinity,
    };
  });
  expect(layout.captchaBottom, JSON.stringify(layout)).toBeLessThanOrEqual(
    layout.buttonTop + 1,
  );
  await page.getByRole('button', { name: '创建友间' }).press('Enter');
  await expect(page).toHaveURL(/\/space\/[0-9a-f-]{36}$/i, {
    timeout: 30_000,
  });
  await expect(page.getByRole('heading', { name: spaceName })).toBeVisible();
});
