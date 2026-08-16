import { expect, test } from '@playwright/test';

const spaceId = '11111111-1111-4111-8111-111111111111';

test('contributors logo returns home with the persisted identity', async ({
  page,
}, testInfo) => {
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

  await page.route('**/rest/v1/rpc/get_my_membership', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: '55555555-5555-4555-8555-555555555555',
        server_now: '2026-07-27T12:00:00.000Z',
        data: {
          membership: {
            member_id: '33333333-3333-4333-8333-333333333333',
            space_id: spaceId,
            display_name: 'Test member',
            role: 'owner',
            status: 'active',
          },
          latest_disabled_membership: null,
        },
      }),
    }),
  );
  await page.route('**/rest/v1/rpc/get_home_snapshot', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: '22222222-2222-4222-8222-222222222222',
        server_now: '2026-07-27T12:00:00.000Z',
        data: {
          space: {
            id: spaceId,
            name: 'Test space',
            timezone: 'Asia/Shanghai',
            active_member_count: 1,
            member_limit: 3,
            daily_checkin_target_minutes: 60,
          },
          me: {
            member_id: '33333333-3333-4333-8333-333333333333',
            display_name: 'Test member',
            role: 'owner',
            profile_timezone: 'Asia/Shanghai',
          },
          my_session: null,
          focusing_members: [],
          today: {
            local_date: '2026-07-27',
            credited_focus_seconds: 0,
            checkin_target_seconds: 3600,
            checkin_completed: false,
            current_streak_days: 0,
            goal_target_minutes: 60,
            goal_source: 'space_default',
            goal_locked: false,
            future_default_target_minutes: 60,
          },
          active_goal_summary: null,
          unseen_achievement: null,
        },
      }),
    }),
  );
  await page.route('**/rest/v1/rpc/get_nav_notifications', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: '77777777-7777-4777-8777-777777777777',
        server_now: '2026-07-27T12:00:00.000Z',
        data: { personal: false, shared: false, proposal: false },
      }),
    }),
  );

  await page.goto(`./space/${spaceId}`);
  const contributorsLink = page.locator('a[href$="feature-contributors.html"]');
  if (testInfo.project.name === 'desktop-chromium') {
    await expect(contributorsLink).toBeVisible();
    await contributorsLink.click();
  } else {
    // The contributor entry lives in the desktop sidebar, which is hidden at
    // mobile breakpoints. The logo return path itself must still work on every
    // supported viewport, so enter the static page directly on mobile.
    await page.goto('./feature-contributors.html');
  }
  await expect(page).toHaveURL(/feature-contributors\.html$/);
  const deadlineContributorRow = page
    .locator('tbody tr')
    .filter({ hasText: 'DDL Reminder' });
  await expect(deadlineContributorRow).toContainText('Juuuu, Jade');

  await page.locator('a[data-app-home]').click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator(`a[href$="/space/${spaceId}"]`)).toBeVisible();
  await expect(
    page.getByRole('heading', { name: '无法确认当前身份' }),
  ).toBeHidden();
});
