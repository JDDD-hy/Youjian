import { expect, test } from '@playwright/test';

const spaceId = '81111111-1111-4111-8111-111111111111';
const sessionId = '82222222-2222-4222-8222-222222222222';

test('offline focus controls remain visible and never claim success', async ({
  context,
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === 'iphone-webkit',
    'Playwright WebKit does not provide reliable context-level offline emulation on Windows.',
  );
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
          id: '84444444-4444-4444-8444-444444444444',
          aud: 'authenticated',
          role: 'authenticated',
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
        request_id: crypto.randomUUID(),
        server_now: new Date().toISOString(),
        data: {
          membership: {
            member_id: '83333333-3333-4333-8333-333333333333',
            space_id: spaceId,
            display_name: '离线测试',
            role: 'owner',
            status: 'active',
          },
          latest_disabled_membership: null,
        },
      }),
    }),
  );
  const session = {
    session_id: sessionId,
    space_id: spaceId,
    member_id: '83333333-3333-4333-8333-333333333333',
    task_name: '保持权威计时',
    category: 'study',
    status: 'focusing',
    started_at: new Date(Date.now() - 10 * 60_000).toISOString(),
    accumulated_focus_seconds: 0,
    active_segment_started_at: new Date(Date.now() - 10 * 60_000).toISOString(),
    paused_at: null,
    auto_settle_at: new Date(Date.now() + 350 * 60_000).toISOString(),
    completed_at: null,
    completion_reason: null,
    credited_focus_seconds: null,
    counts_toward_stats: null,
    connection: { status: 'connected', last_seen_at: new Date().toISOString() },
  };
  await page.route('**/rest/v1/rpc/get_home_snapshot', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: crypto.randomUUID(),
        server_now: new Date().toISOString(),
        data: {
          space: {
            id: spaceId,
            name: '离线友间',
            timezone: 'Asia/Shanghai',
            active_member_count: 1,
            member_limit: 3,
            daily_checkin_target_minutes: 60,
          },
          me: {
            member_id: session.member_id,
            display_name: '离线测试',
            role: 'owner',
            profile_timezone: 'Asia/Shanghai',
          },
          my_session: session,
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
  await page.route('**/rest/v1/rpc/heartbeat_focus', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        ok: true,
        request_id: crypto.randomUUID(),
        server_now: new Date().toISOString(),
        data: { session },
      }),
    }),
  );

  await page.goto(`./space/${spaceId}`);
  const pause = page.getByRole('button', { name: '暂停' });
  await expect(pause).toBeVisible();
  await context.setOffline(true);
  await expect(pause).toBeEnabled();
  await pause.click();
  await expect(page.getByText(/这次操作还没有生效/)).toBeVisible();
  await expect(page.getByRole('button', { name: '暂停' })).toBeVisible();
  await expect(page.getByRole('button', { name: '继续专注' })).toHaveCount(0);
  await context.setOffline(false);
});
