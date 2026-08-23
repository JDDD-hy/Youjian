import { expect, test } from '@playwright/test';
import { randomUUID } from 'node:crypto';

test('two devices create, join, synchronize focus, and restore identity', async ({
  browser,
  page: owner,
}) => {
  test.setTimeout(120_000);
  const suffix = randomUUID().slice(0, 8);
  const spaceName = `双设备友间-${suffix}`;
  const taskName = `同步任务-${suffix}`;
  const revisedTaskName = `修改后的任务-${suffix}`;
  const lifeTaskName = `生活任务-${suffix}`;
  const memberName = `成员-${suffix}`;

  await owner.goto('./create');
  if (process.env.E2E_EXPECT_CAPTCHA !== '0')
    await expect(owner.locator('[name="cf-turnstile-response"]')).toHaveValue(
      /.+/,
      { timeout: 30_000 },
    );
  await owner.getByLabel('你的昵称').fill(`房主-${suffix}`);
  await owner.getByLabel('友间名称').fill(spaceName);
  await owner.getByRole('checkbox').check();
  await owner.getByRole('button', { name: '创建友间' }).press('Enter');
  await expect(owner).toHaveURL(/\/space\/[0-9a-f-]{36}$/i, {
    timeout: 30_000,
  });
  await expect(owner.getByRole('heading', { name: spaceName })).toBeVisible();

  const spaceId = new URL(owner.url()).pathname.split('/').at(-1)!;
  const inviteUrl = await owner.evaluate(
    (id) => localStorage.getItem(`youjian:invite:${id}`),
    spaceId,
  );
  expect(inviteUrl).toMatch(/\/invite\//);
  expect(new URL(inviteUrl!).origin).toBe(new URL(owner.url()).origin);

  const memberContext = await browser.newContext();
  const member = await memberContext.newPage();
  try {
    await member.goto('./join');
    await member.getByLabel('你的昵称').fill(memberName);
    await member.getByRole('button', { name: '保存并等待' }).click();
    await expect(
      member.getByText('昵称已保存在这台设备。', { exact: false }),
    ).toBeVisible();
    await member.goto(inviteUrl!);
    await expect(
      member.getByRole('heading', { name: `加入「${spaceName}」` }),
    ).toBeVisible();
    if (process.env.E2E_EXPECT_CAPTCHA !== '0')
      await expect(
        member.locator('[name="cf-turnstile-response"]'),
      ).toHaveValue(/.+/, { timeout: 30_000 });
    await expect(member.getByLabel('你在这里使用的昵称')).toHaveValue(
      memberName,
    );
    await member.getByRole('button', { name: '加入友间' }).press('Enter');
    await expect(member).toHaveURL(new RegExp(`/space/${spaceId}$`), {
      timeout: 30_000,
    });
    await expect(
      member.getByRole('heading', { name: spaceName }),
    ).toBeVisible();

    await owner.getByRole('button', { name: '开始专注' }).click();
    await owner.getByLabel('任务名称').fill(taskName);
    await owner.getByRole('button', { name: '点亮台灯' }).click();
    await expect(
      owner.getByRole('button', { name: '知道了，点亮台灯' }),
    ).toBeVisible();
    await owner.getByRole('button', { name: '知道了，点亮台灯' }).click();
    await expect(owner.getByRole('heading', { name: taskName })).toBeVisible();
    await expect(member.getByText(taskName, { exact: true })).toBeVisible({
      timeout: 15_000,
    });

    await owner.getByRole('button', { name: '修改任务' }).click();
    const editDialog = owner.getByRole('dialog', { name: '修改当前任务' });
    await editDialog
      .getByRole('textbox', { name: /任务名称/ })
      .fill(revisedTaskName);
    await editDialog.getByRole('radio', { name: '娱乐' }).check();
    await editDialog.getByRole('button', { name: '保存修改' }).click();
    await expect(
      owner.getByRole('heading', { name: revisedTaskName }),
    ).toBeVisible();
    await expect(
      member.getByText(revisedTaskName, { exact: true }),
    ).toBeVisible({ timeout: 15_000 });
    await expect(
      owner.locator('[data-lamp-variant="entertainment-focusing"]'),
    ).toBeVisible();
    const memberCard = member.locator('article').filter({
      has: member.getByText(revisedTaskName, { exact: true }),
    });
    await expect(
      memberCard.locator('[data-lamp-variant="entertainment-focusing"]'),
    ).toBeVisible();
    const memberHistory = member.getByRole('button', { name: /查看旧任务/ });
    await memberHistory.click();
    await expect(member.getByText(taskName, { exact: true })).toBeVisible();
    await expect(member.getByText(/学习.*修改于/)).toBeVisible();
    await member.getByRole('button', { name: /收起旧任务/ }).click();

    await owner.getByRole('button', { name: '暂停' }).click();
    await expect(owner.getByRole('button', { name: '继续专注' })).toBeVisible();
    await expect(owner.locator('[data-lamp-variant="paused"]')).toBeVisible();
    await expect(member.getByText(revisedTaskName, { exact: true })).toBeHidden(
      { timeout: 15_000 },
    );

    await owner.getByRole('button', { name: '继续专注' }).click();
    await expect(
      member.getByText(revisedTaskName, { exact: true }),
    ).toBeVisible({ timeout: 15_000 });
    await expect(
      owner.locator('[data-lamp-variant="entertainment-focusing"]'),
    ).toBeVisible();
    await expect(
      memberCard.locator('[data-lamp-variant="entertainment-focusing"]'),
    ).toBeVisible();

    await owner.reload();
    await expect(
      owner.locator('[data-lamp-variant="entertainment-focusing"]'),
    ).toBeVisible();

    await owner.getByRole('button', { name: '修改任务' }).click();
    const lifeDialog = owner.getByRole('dialog', { name: '修改当前任务' });
    await lifeDialog
      .getByRole('textbox', { name: /任务名称/ })
      .fill(lifeTaskName);
    await lifeDialog.getByRole('radio', { name: '生活' }).check();
    await lifeDialog.getByRole('button', { name: '保存修改' }).click();
    await expect(
      owner.getByRole('heading', { name: lifeTaskName }),
    ).toBeVisible();
    await expect(member.getByText(lifeTaskName, { exact: true })).toBeVisible({
      timeout: 15_000,
    });
    await expect(owner.locator('[data-lamp-variant="focusing"]')).toBeVisible();
    const lifeMemberCard = member.locator('article').filter({
      has: member.getByText(lifeTaskName, { exact: true }),
    });
    await expect(
      lifeMemberCard.locator('[data-lamp-variant="focusing"]'),
    ).toBeVisible();

    await owner.getByRole('button', { name: '结束本次' }).click();
    await owner.getByRole('button', { name: '确认结束' }).click();
    await expect(member.getByText(lifeTaskName, { exact: true })).toBeHidden({
      timeout: 15_000,
    });

    await owner.reload();
    await member.reload();
    await expect(owner.getByRole('heading', { name: spaceName })).toBeVisible();
    await expect(
      member.getByRole('heading', { name: spaceName }),
    ).toBeVisible();
  } finally {
    await memberContext.close();
  }
});
