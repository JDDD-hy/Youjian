import { expect, test } from '@playwright/test';

const spaceId = '11111111-1111-4111-8111-111111111111';

test('idle room renders the authoritative snapshot without viewport overflow', async ({
  page,
}) => {
  let savedGoal: Record<string, unknown> | null = null;
  await page.addInitScript(() => {
    localStorage.setItem(
      'sb-127-auth-token',
      JSON.stringify({
        access_token: 'test-access',
        refresh_token: 'test-refresh',
        expires_at: 4102444800,
        expires_in: 3600,
        token_type: 'bearer',
        user: {
          id: '44444444-4444-4444-8444-444444444444',
          aud: 'authenticated',
          role: 'authenticated',
          created_at: '2026-07-27T00:00:00.000Z',
          updated_at: '2026-07-27T00:00:00.000Z',
          app_metadata: {},
          user_metadata: {},
        },
      }),
    );
  });
  await page.route('**/rest/v1/rpc/get_my_membership', async (route) => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: '55555555-5555-4555-8555-555555555555',
        server_now: '2026-07-27T12:00:00.000Z',
        data: {
          membership: {
            member_id: '33333333-3333-4333-8333-333333333333',
            space_id: spaceId,
            display_name: '陈宇',
            role: 'owner',
            status: 'active',
          },
          latest_disabled_membership: null,
        },
      }),
    });
  });
  await page.route('**/rest/v1/rpc/get_home_snapshot', async (route) => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: '22222222-2222-4222-8222-222222222222',
        server_now: '2026-07-27T12:00:00.000Z',
        data: {
          space: {
            id: spaceId,
            name: '我们的友间',
            timezone: 'Asia/Shanghai',
            active_member_count: 2,
            member_limit: 3,
            daily_checkin_target_minutes: 60,
          },
          me: {
            member_id: '33333333-3333-4333-8333-333333333333',
            display_name: '陈宇',
            role: 'owner',
            profile_timezone: 'Asia/Shanghai',
          },
          my_session: null,
          focusing_members: [],
          today: {
            local_date: '2026-07-27',
            credited_focus_seconds: 2280,
            checkin_target_seconds: 3600,
            checkin_completed: false,
            current_streak_days: 6,
            goal_target_minutes: 60,
            goal_source: 'space_default',
            goal_locked: false,
            future_default_target_minutes: 60,
          },
          active_goal_summary: null,
          unseen_achievement: null,
        },
      }),
    });
  });
  await page.route('**/rest/v1/rpc/set_personal_daily_goal', async (route) => {
    savedGoal = route.request().postDataJSON() as Record<string, unknown>;
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: '66666666-6666-4666-8666-666666666666',
        server_now: '2026-07-27T12:00:00.000Z',
        data: {
          scope: 'today',
          target_minutes: 45,
          effective_date: '2026-07-27',
        },
      }),
    });
  });

  await page.goto(`./space/${spaceId}`);
  await expect(page.getByRole('heading', { name: '我们的友间' })).toBeVisible();
  await expect(page.getByRole('button', { name: '开始专注' })).toBeVisible();
  await page.getByRole('button', { name: '修改目标 · 60 分钟' }).click();
  const goalDialog = page.getByRole('dialog', { name: '修改每日专注目标' });
  await expect(goalDialog).toBeVisible();
  await goalDialog.getByLabel('目标时长（分钟）').fill('45');
  await goalDialog.getByRole('button', { name: '保存目标' }).click();
  await expect(goalDialog).toBeHidden();
  expect(savedGoal).toMatchObject({ p_scope: 'today', p_target_minutes: 45 });
  await page.getByRole('button', { name: '开始专注' }).click();
  await expect(
    page.getByRole('dialog', { name: '这次想专注什么？' }),
  ).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(
    page.getByRole('dialog', { name: '这次想专注什么？' }),
  ).toBeHidden();
  const coarsePointer = await page.evaluate(
    () => window.matchMedia('(pointer: coarse)').matches,
  );
  if (!coarsePointer) {
    await expect(page.getByRole('button', { name: '开始专注' })).toBeFocused();
  }
  const viewportWidth = page.viewportSize()?.width;
  expect(
    await page.evaluate(
      (configuredWidth) =>
        document.documentElement.scrollWidth >
        Math.ceil(
          configuredWidth ??
            window.visualViewport?.width ??
            document.documentElement.clientWidth,
        ) +
          1,
      viewportWidth,
    ),
  ).toBe(false);
});
