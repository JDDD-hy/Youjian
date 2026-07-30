import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

test('owner rotates a same-origin invite while members cannot manage it', async ({
  browser,
  page: owner,
}) => {
  test.setTimeout(120_000);
  const suffix = randomUUID().slice(0, 8);
  const spaceName = `邀请权限友间-${suffix}`;

  await owner.addInitScript(() => {
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: (data: ShareData) => {
        sessionStorage.setItem('youjian:e2e-share-title', data.title ?? '');
        sessionStorage.setItem('youjian:e2e-share-url', data.url ?? '');
        return Promise.resolve();
      },
    });
  });

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
    await expect(
      member.getByRole('button', { name: '分享邀请链接' }),
    ).toHaveCount(0);
    await expect(member.getByRole('button', { name: '停用' })).toHaveCount(0);

    await owner.goto(`/space/${spaceId}/goals`);
    await owner.getByRole('button', { name: '发起提案' }).click();
    await owner.getByRole('button', { name: '下一步' }).click();
    await owner.getByLabel('目标值（分钟）').fill('30');
    await owner.getByRole('button', { name: '下一步' }).click();
    await owner.getByRole('button', { name: '发起并投同意票' }).click();
    await expect(
      owner.getByRole('heading', { name: '等待投票' }),
    ).toBeVisible();
    await expect(
      owner.getByText('1 / 2 人已同意', { exact: false }),
    ).toBeVisible();

    await member.goto(`/space/${spaceId}/goals`);
    await expect(
      member.getByText('1 / 2 人已同意', { exact: false }),
    ).toBeVisible();
    await member.getByRole('button', { name: '同意' }).click();
    await expect(member.getByRole('heading', { name: '即将开始' })).toBeVisible(
      { timeout: 30_000 },
    );

    await owner.goto(`/space/${spaceId}/settings`);
    await expect(
      owner.getByRole('button', { name: '分享邀请链接' }),
    ).toBeVisible();
    await owner.getByRole('button', { name: '分享邀请链接' }).click();
    const sharedInvite = await owner.evaluate(() => ({
      title: sessionStorage.getItem('youjian:e2e-share-title'),
      url: sessionStorage.getItem('youjian:e2e-share-url'),
    }));
    expect(sharedInvite).toMatchObject({
      title: `加入「${spaceName}」`,
      url: oldInviteUrl,
    });
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

    await owner.goto(`/space/${spaceId}/settings`);
    await owner.getByRole('button', { name: '停用' }).click();
    await owner.getByRole('button', { name: '确认停用' }).click();
    await expect(owner.getByText('已停用', { exact: true })).toBeVisible({
      timeout: 30_000,
    });

    await member.reload();
    await expect(
      member.getByRole('heading', { name: '成员身份已停用' }),
    ).toBeVisible({ timeout: 30_000 });
  } finally {
    await memberContext.close();
  }
});
