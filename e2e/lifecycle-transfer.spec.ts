import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

async function createSpace(
  page: import('@playwright/test').Page,
  suffix: string,
) {
  await page.goto('./create');
  if (process.env.E2E_EXPECT_CAPTCHA !== '0')
    await expect(page.locator('[name="cf-turnstile-response"]')).toHaveValue(
      /.+/,
      { timeout: 30_000 },
    );
  await page.getByLabel('你的昵称').fill(`房主-${suffix}`);
  await page.getByLabel('友间名称').fill(`生命周期友间-${suffix}`);
  await page.getByRole('checkbox').check();
  await page.getByRole('button', { name: '创建友间' }).click();
  await expect(page).toHaveURL(/\/space\/[0-9a-f-]{36}$/i, {
    timeout: 30_000,
  });
}

test('owner transfers ownership, former owner leaves, and new owner dissolves', async ({
  browser,
  page: owner,
}) => {
  test.setTimeout(180_000);
  const suffix = randomUUID().slice(0, 8);
  await createSpace(owner, suffix);
  const spaceId = new URL(owner.url()).pathname.split('/').at(-1)!;
  const inviteUrl = await owner.evaluate(
    (id) => localStorage.getItem(`youjian:invite:${id}`),
    spaceId,
  );

  const memberContext = await browser.newContext();
  const member = await memberContext.newPage();
  try {
    await member.goto(inviteUrl!);
    if (process.env.E2E_EXPECT_CAPTCHA !== '0')
      await expect(
        member.locator('[name="cf-turnstile-response"]'),
      ).toHaveValue(/.+/, { timeout: 30_000 });
    await member.getByLabel('你在这里使用的昵称').fill(`成员-${suffix}`);
    await member.getByRole('button', { name: '加入友间' }).click();
    await expect(member).toHaveURL(new RegExp(`/space/${spaceId}$`), {
      timeout: 30_000,
    });

    await owner.goto(`./space/${spaceId}/settings`);
    await owner.getByRole('button', { name: '转让房主' }).click();
    await owner.getByRole('button', { name: '确认转让' }).click();
    await expect(owner.getByText('成员', { exact: true }).first()).toBeVisible({
      timeout: 30_000,
    });

    await owner.getByRole('button', { name: '主动退出友间' }).click();
    await owner.getByRole('button', { name: '确认退出友间' }).click();
    await expect(owner).toHaveURL(/\/(?:Youjian)?\/?$/, { timeout: 30_000 });
    await expect(owner.getByText('可凭当前有效邀请重新加入')).toBeVisible();

    await owner.goto(inviteUrl!);
    if (process.env.E2E_EXPECT_CAPTCHA !== '0')
      await expect(
        owner.locator('[name="cf-turnstile-response"]'),
      ).toHaveValue(/.+/, { timeout: 30_000 });
    await owner.getByLabel('你在这里使用的昵称').fill(`重新加入-${suffix}`);
    await owner.getByRole('button', { name: '加入友间' }).click();
    await expect(owner).toHaveURL(new RegExp(`/space/${spaceId}$`), {
      timeout: 30_000,
    });

    await member.goto(`./space/${spaceId}/settings`);
    await expect(
      member.getByText('房主', { exact: true }).first(),
    ).toBeVisible();
    await member.getByRole('button', { name: '解散友间' }).click();
    await member.getByRole('button', { name: '确认永久解散' }).click();
    await expect(member).toHaveURL(/\/(?:Youjian)?\/?$/, { timeout: 30_000 });

    const freshContext = await browser.newContext();
    try {
      const fresh = await freshContext.newPage();
      await fresh.goto(inviteUrl!);
      await expect(
        fresh.getByRole('heading', { name: '这个邀请已失效' }),
      ).toBeVisible({ timeout: 30_000 });
    } finally {
      await freshContext.close();
    }
  } finally {
    await memberContext.close();
  }
});

test('one-time code moves identity and revokes the old device', async ({
  browser,
  page: oldDevice,
}) => {
  test.setTimeout(120_000);
  const suffix = randomUUID().slice(0, 8);
  await createSpace(oldDevice, suffix);
  const spaceId = new URL(oldDevice.url()).pathname.split('/').at(-1)!;

  await oldDevice.goto(`./space/${spaceId}/settings`);
  await oldDevice.getByRole('button', { name: '生成身份迁移码' }).click();
  const code = (
    await oldDevice.getByLabel('一次性身份迁移码').textContent()
  )?.trim();
  expect(code).toMatch(/^[A-Za-z0-9_-]{32}$/);

  const newContext = await browser.newContext();
  const newDevice = await newContext.newPage();
  try {
    await newDevice.goto('./transfer');
    if (process.env.E2E_EXPECT_CAPTCHA !== '0')
      await expect(
        newDevice.locator('[name="cf-turnstile-response"]'),
      ).toHaveValue(/.+/, { timeout: 30_000 });
    await newDevice.getByLabel('迁移码').fill(code!);
    await newDevice.getByRole('button', { name: '迁移到这台设备' }).click();
    await expect(newDevice).toHaveURL(new RegExp(`/space/${spaceId}$`), {
      timeout: 30_000,
    });

    await oldDevice.reload();
    await expect(oldDevice).toHaveURL(/\/(?:Youjian)?\/?$/, {
      timeout: 30_000,
    });
    await expect(
      oldDevice.getByRole('link', { name: '创建友间' }),
    ).toBeVisible();
    expect(
      await oldDevice.evaluate(() =>
        Object.keys(localStorage).filter((key) => key.startsWith('youjian:')),
      ),
    ).toEqual([]);
    await oldDevice.goto('./create');
    await expect(oldDevice.getByRole('heading', { name: '创建友间' })).toBeVisible();

    const replayContext = await browser.newContext();
    try {
      const replay = await replayContext.newPage();
      await replay.goto('./transfer');
      if (process.env.E2E_EXPECT_CAPTCHA !== '0')
        await expect(
          replay.locator('[name="cf-turnstile-response"]'),
        ).toHaveValue(/.+/, { timeout: 30_000 });
      await replay.getByLabel('迁移码').fill(code!);
      await replay.getByRole('button', { name: '迁移到这台设备' }).click();
      await expect(replay.getByText('这个迁移码已经使用过')).toBeVisible({
        timeout: 30_000,
      });
    } finally {
      await replayContext.close();
    }
  } finally {
    await newContext.close();
  }
});
