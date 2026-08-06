import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

test.use({ serviceWorkers: 'block' });

test('owner rotates a same-origin invite while members cannot manage it', async ({
  browser,
  page: owner,
}) => {
  test.setTimeout(180_000);
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

  await owner.goto('./create');
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
  expect(new URL(oldInviteUrl!).pathname).toMatch(
    new RegExp(`/(?:Youjian/)?invite/[A-Za-z0-9_-]{40,128}$`),
  );

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

    await member.goto(`./space/${spaceId}/settings`);
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
    await expect(member.getByRole('button', { name: '修改名称' })).toHaveCount(
      0,
    );
    await expect(member.getByRole('button', { name: '提高上限' })).toHaveCount(
      0,
    );

    const renamedSpace = `新名字-${suffix}`;
    await owner.goto(`./space/${spaceId}/settings`);
    await owner.getByRole('button', { name: '修改名称' }).click();
    await owner.getByLabel('新名称').fill(`  ${renamedSpace}  `);
    await owner.getByRole('button', { name: '保存名称' }).click();
    await expect(
      owner.getByRole('heading', { level: 2, name: renamedSpace }),
    ).toBeVisible();

    await owner.getByRole('button', { name: '提高上限' }).click();
    await owner.getByLabel('新上限').selectOption('5');
    await expect(
      owner.getByText('保存后不能调低', { exact: false }),
    ).toBeVisible();
    await owner.getByRole('button', { name: '确认提高' }).click();
    await expect(
      owner.getByRole('definition').filter({ hasText: '5 人' }),
    ).toBeVisible();
    expect(
      await owner.evaluate((key) => localStorage.getItem(key), storageKey),
    ).toBe(oldInviteUrl);

    const previewContext = await browser.newContext();
    const preview = await previewContext.newPage();
    try {
      await preview.goto(oldInviteUrl!);
      await expect(
        preview.getByRole('heading', { name: `加入「${renamedSpace}」` }),
      ).toBeVisible();
      await expect(preview.getByText('2 / 5 人')).toBeVisible();
    } finally {
      await previewContext.close();
    }

    await member.reload();
    await expect(
      member.getByRole('heading', { level: 2, name: renamedSpace }),
    ).toBeVisible();

    await owner.route('**/rest/v1/rpc/list_achievements', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          ok: true,
          request_id: randomUUID(),
          server_now: new Date().toISOString(),
          data: {
            space_id: spaceId,
            items: [
              {
                achievement_id: randomUUID(),
                achievement_type: 'together_streak',
                tier: 'gold',
                earned_at: new Date().toISOString(),
                metadata: { days: 7 },
                count: 3,
                participants_recorded: true,
                participants: [
                  {
                    member_id: 'a',
                    display_name: `房主-${suffix}`,
                    participation_days: 7,
                  },
                  {
                    member_id: 'b',
                    display_name: `成员-${suffix}`,
                    participation_days: 7,
                  },
                ],
                seen: true,
              },
            ],
            next_cursor: null,
          },
        }),
      });
    });
    await owner.route(
      '**/rest/v1/rpc/list_personal_achievements',
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            ok: true,
            request_id: randomUUID(),
            server_now: new Date().toISOString(),
            data: {
              space_id: spaceId,
              items: [
                {
                  achievement_id: 'night_owl',
                  achievement_type: 'night_owl',
                  tier: 'gold',
                  earned_at: new Date().toISOString(),
                  first_earned_at: new Date().toISOString(),
                  last_earned_at: new Date().toISOString(),
                  count: 1,
                  metadata: {},
                  seen: true,
                },
              ],
              next_cursor: null,
            },
          }),
        });
      },
    );
    await owner.goto(`./space/${spaceId}/goals`);
    await expect(
      owner.getByRole('heading', { name: '挑灯夜战' }),
    ).toBeVisible();
    await expect(owner.getByText(/累计达成/)).toHaveCount(0);
    await owner.getByRole('tab', { name: '共同成就' }).click();
    const achievementHeading = owner.getByRole('heading', {
      name: '7 日相伴',
    });
    await expect(achievementHeading).toBeVisible();
    await expect(owner.getByText('金级', { exact: true })).toHaveCount(0);
    await expect(owner.getByText(/累计达成/)).toHaveCount(0);
    await expect(
      achievementHeading.locator('..').locator('.achievement-card__icon--gold'),
    ).toBeVisible();
    const goldCard = achievementHeading.locator('..');
    const goldIcon = goldCard.locator('.achievement-card__icon--gold');
    await expect
      .poll(() =>
        goldCard.evaluate((element) => getComputedStyle(element).borderColor),
      )
      .toBe('rgb(150, 109, 10)');
    await expect
      .poll(() =>
        goldIcon.evaluate((element) => getComputedStyle(element).color),
      )
      .toBe('rgb(150, 109, 10)');
    const conditionTrigger = achievementHeading
      .locator('..')
      .getByRole('button', { name: /达成条件/ });
    await conditionTrigger.hover();
    await expect(conditionTrigger.getByRole('tooltip')).toBeVisible();
    const participantTrigger = achievementHeading
      .locator('..')
      .getByRole('button', { name: /一起达成的人/ });
    await participantTrigger.hover();
    await expect(participantTrigger.getByRole('tooltip')).toContainText(
      `房主-${suffix}（7 天）、成员-${suffix}（7 天）`,
    );
    await owner.getByRole('button', { name: '发起提案' }).click();
    await owner.getByRole('button', { name: '下一步' }).click();
    await owner.getByLabel('目标值（分钟）').fill('30');
    await owner.getByRole('button', { name: '下一步' }).click();
    await expect(
      owner.getByText('若今天全员通过', { exact: false }),
    ).toBeVisible();
    await owner.getByRole('button', { name: '发起并投同意票' }).click();
    await expect(
      owner.getByRole('heading', { name: '等待投票' }),
    ).toBeVisible();
    await expect(
      owner.getByText('1 / 2 人已同意', { exact: false }),
    ).toBeVisible();

    await member.goto(`./space/${spaceId}/goals`);
    await expect(
      member.getByText('1 / 2 人已同意', { exact: false }),
    ).toBeVisible();
    await member.getByRole('button', { name: '同意' }).click();
    await expect(member.getByRole('heading', { name: '即将开始' })).toBeVisible(
      { timeout: 30_000 },
    );
    await expect(
      member.getByRole('button', { name: '发起提案' }),
    ).toBeDisabled();

    await owner.goto(`./space/${spaceId}/settings`);
    await expect(
      owner.getByRole('button', { name: '分享邀请链接' }),
    ).toBeVisible();
    await owner.getByRole('button', { name: '分享邀请链接' }).click();
    const sharedInvite = await owner.evaluate(() => ({
      title: sessionStorage.getItem('youjian:e2e-share-title'),
      url: sessionStorage.getItem('youjian:e2e-share-url'),
    }));
    expect(sharedInvite).toMatchObject({
      title: `加入「${renamedSpace}」`,
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
    expect(new URL(newInviteUrl!).pathname).toMatch(
      new RegExp(`/(?:Youjian/)?invite/[A-Za-z0-9_-]{40,128}$`),
    );

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
        newInvite.getByRole('heading', { name: `加入「${renamedSpace}」` }),
      ).toBeVisible();
    } finally {
      await newInviteContext.close();
    }

    await owner.goto(`./space/${spaceId}/settings`);
    await owner.getByRole('button', { name: '停用' }).click();
    await owner.getByRole('button', { name: '确认停用' }).click();
    await expect(owner.getByText('已停用', { exact: true })).toBeVisible({
      timeout: 30_000,
    });

    await member.reload();
    await expect(
      member.getByRole('heading', { name: '成员身份已停用' }),
    ).toBeVisible({ timeout: 30_000 });

    await owner.getByRole('button', { name: '退出当前设备' }).click();
    await owner.getByRole('button', { name: '确认退出' }).click();
    await expect(owner).toHaveURL(/\/(?:Youjian\/?)?$/, { timeout: 30_000 });
    await expect(owner.getByRole('heading', { name: '友间' })).toBeVisible();
    expect(
      await owner.evaluate(() =>
        Object.keys(localStorage).filter((key) => key.startsWith('youjian:')),
      ),
    ).toEqual([]);
  } finally {
    await memberContext.close();
  }
});
