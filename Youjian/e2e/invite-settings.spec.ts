import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

test('owner rotates a same-origin invite while members cannot manage it', async ({
  browser,
  page: owner,
}) => {
  test.setTimeout(120_000);
  const suffix = randomUUID().slice(0, 8);
  const spaceName = `邀请权限友间-${suffix}`;

  await owner.goto('/create');
  if (process.env.E2E_EXPECT_CAPTCHA !== '0')
    await expect(owner.locator('[name="cf-turnstile-response"]')).toHaveValue(
      /.+/,
      { timeout: 30_000 },
    );
  await owner.getByLabel('你的昵称').fill(`房主-${suffix}`);
  await owner.getByLabel('友间名称').fill(spaceName);
  await owner.getByRole('checkbox').check();
  await owner.getByRole('button', { name: '创建友间' }).click();
  await expect(owner).toHaveURL(/\/space\/[0-9a-f-]{36}$/i, {
    timeout: 30_000,
  });

  const spaceId = new URL(owner.url()).pathname.split('/').at(-1)!;
  const storageKey = `youjian:invite:${spaceId}`;
  const oldInviteUrl = await owner.evaluate(
    (key) => localStorage.getItem(key),
    storageKey,
  );
  expect(oldInviteUrl).toBeTruthy();
  expect(new URL(oldInviteUrl!).origin).toBe(new URL(owner.url()).origin);

  const memberContext = await browser.newContext();
  const member = await memberContext.newPage();
  try {
    await member.goto(oldInviteUrl!);
    await expect(
      member.getByRole('heading', { name: `加入「${spaceName}」` }),
    ).toBeVisible();
    if (process.env.E2E_EXPECT_CAPTCHA !== '0')
      await expect(
        member.locator('[name="cf-turnstile-response"]'),
      ).toHaveValue(/.+/, { timeout: 30_000 });
    await member.getByLabel('你在这里使用的昵称').fill(`成员-${suffix}`);
    await member.getByRole('button', { name: '加入友间' }).click();
    await expect(member).toHaveURL(new RegExp(`/space/${spaceId}$`), {
      timeout: 30_000,
    });

    await member.goto(`/space/${spaceId}/settings`);
    await expect(member.getByRole('heading', { name: '设置' })).toBeVisible();
    await expect(
      member.getByRole('heading', { level: 2, name: spaceName }),
    ).toBeVisible();
    await expect(
      member.getByRole('button', { name: '轮换邀请链接' }),
    ).toHaveCount(0);
    await expect(member.getByRole('button', { name: '停用' })).toHaveCount(0);

    await owner.goto(`/space/${spaceId}/settings`);
    await owner.getByRole('button', { name: '轮换邀请链接' }).click();
    await owner.getByRole('button', { name: '确认轮换' }).click();

    await expect
      .poll(
        () => owner.evaluate((key) => localStorage.getItem(key), storageKey),
        { timeout: 30_000 },
      )
      .not.toBe(oldInviteUrl);
    const newInviteUrl = await owner.evaluate(
      (key) => localStorage.getItem(key),
      storageKey,
    );
    expect(newInviteUrl).toBeTruthy();
    expect(new URL(newInviteUrl!).origin).toBe(new URL(owner.url()).origin);

    const oldInviteContext = await browser.newContext();
    const oldInvite = await oldInviteContext.newPage();
    try {
      await oldInvite.goto(oldInviteUrl!);
      await expect(
        oldInvite.getByRole('heading', { name: '这个邀请已失效' }),
      ).toBeVisible();
    } finally {
      await oldInviteContext.close();
    }

    const newInviteContext = await browser.newContext();
    const newInvite = await newInviteContext.newPage();
    try {
      await newInvite.goto(newInviteUrl!);
      await expect(
        newInvite.getByRole('heading', { name: `加入「${spaceName}」` }),
      ).toBeVisible();
    } finally {
      await newInviteContext.close();
    }
  } finally {
    await memberContext.close();
  }
});
