import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

function timerSeconds(value: string | null) {
  const parts = (value ?? '').split(':').map(Number);
  if (parts.length !== 3 || parts.some((part) => !Number.isFinite(part)))
    return -1;
  return parts[0] * 3600 + parts[1] * 60 + parts[2];
}

test('deployed timer advances, excludes pauses, and settles authoritatively', async ({
  page,
}) => {
  const fullTiming = process.env.E2E_FULL_TIMING === '1';
  test.setTimeout(fullTiming ? 420_000 : 90_000);
  const suffix = randomUUID().slice(0, 8);
  const taskName = `线上计时-${suffix}`;

  await page.goto('./create');
  if (process.env.E2E_EXPECT_CAPTCHA !== '0')
    await expect(page.locator('[name="cf-turnstile-response"]')).toHaveValue(
      /.+/,
      { timeout: 30_000 },
    );
  await page.getByLabel('你的昵称').fill(`计时员-${suffix}`);
  await page.getByLabel('友间名称').fill(`线上验收-${suffix}`);
  await page.getByRole('checkbox').check();
  await page.getByRole('button', { name: '创建友间' }).click();
  await expect(page).toHaveURL(/\/space\/[0-9a-f-]{36}$/i, {
    timeout: 30_000,
  });

  await page.getByRole('button', { name: '开始专注' }).click();
  await page.getByLabel('任务名称').fill(taskName);
  await page.getByRole('button', { name: '点亮台灯' }).click();
  await expect(
    page.getByRole('button', { name: '知道了，点亮台灯' }),
  ).toBeVisible();
  await page.getByRole('button', { name: '知道了，点亮台灯' }).click();

  const timer = page.locator('.timer');
  await expect(timer).toHaveCount(1);
  await expect
    .poll(async () => timerSeconds(await timer.textContent()))
    .toBeGreaterThanOrEqual(3);

  await page.getByRole('button', { name: '暂停' }).click();
  await expect(page.getByRole('button', { name: '继续专注' })).toBeVisible();
  const pausedAt = timerSeconds(await timer.textContent());
  await page.waitForTimeout(3_000);
  expect(timerSeconds(await timer.textContent())).toBe(pausedAt);

  await page.getByRole('button', { name: '继续专注' }).click();
  await expect(page.getByRole('button', { name: '暂停' })).toBeVisible();
  const settlementThreshold = fullTiming ? 302 : pausedAt + 3;
  await expect
    .poll(async () => timerSeconds(await timer.textContent()), {
      timeout: fullTiming ? 330_000 : 15_000,
    })
    .toBeGreaterThanOrEqual(settlementThreshold);

  await page.getByRole('button', { name: '结束本次' }).click();
  if (!fullTiming) await page.getByRole('button', { name: '确认结束' }).click();

  await expect(
    page.getByRole('heading', {
      name: fullTiming ? '专注完成' : '这一小段已记录',
    }),
  ).toBeVisible();
  await expect(page.locator('.result-card > strong')).toHaveText(
    fullTiming ? /5 分钟/ : '0 分钟',
  );

  await page.getByRole('link', { name: '查看记录' }).click();
  await expect(page.getByRole('heading', { name: '统计' })).toBeVisible();
  await expect(page.getByText(taskName, { exact: true })).toBeVisible();
});
