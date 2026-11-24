import { expect, test } from '@playwright/test';

const spaceId = '11111111-1111-4111-8111-111111111111';

for (const scenario of [
  'success',
  'membership-retry',
  'invalid-code',
] as const) {
  test(`identity recovery feedback: ${scenario}`, async ({
    page,
  }, testInfo) => {
    let redeemed = 0;
    let membershipRequests = 0;
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
            app_metadata: {},
            user_metadata: {},
          },
        }),
      );
    });
    await page.route('**/rest/v1/rpc/**', async (route) => {
      const name = new URL(route.request().url()).pathname.split('/').pop();
      let data: unknown = {};
      if (name === 'redeem_identity_recovery_code') {
        redeemed++;
        await new Promise((resolve) => setTimeout(resolve, 150));
        if (scenario === 'invalid-code') {
          await route.fulfill({
            json: { ok: false, error: { code: 'INVALID_RECOVERY_CODE' } },
          });
          return;
        }
        data = { transferred: true };
      } else if (name === 'get_my_membership') {
        membershipRequests++;
        if (scenario === 'membership-retry' && membershipRequests === 1) {
          await route.fulfill({
            json: { ok: false, error: { code: 'UNAVAILABLE' } },
          });
          return;
        }
        data = {
          membership: {
            member_id: '33333333-3333-4333-8333-333333333333',
            space_id: spaceId,
            display_name: 'jade',
            role: 'member',
            status: 'active',
          },
          latest_disabled_membership: null,
        };
      } else if (name === 'get_home_snapshot') {
        data = {
          space: {
            id: spaceId,
            name: 'JJJJ',
            timezone: 'Europe/Paris',
            active_member_count: 1,
            member_limit: 3,
            daily_checkin_target_minutes: 60,
          },
          me: {
            member_id: '33333333-3333-4333-8333-333333333333',
            display_name: 'jade',
            role: 'member',
            profile_timezone: 'Europe/Paris',
          },
          my_session: null,
          focusing_members: [],
          today: {
            local_date: '2026-11-24',
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
        };
      } else if (name === 'get_nav_notifications') {
        data = { personal: false, shared: false, proposal: false };
      }
      await route.fulfill({
        json: {
          ok: true,
          data,
          request_id: 'browser-test',
          server_now: new Date().toISOString(),
        },
      });
    });
    await page.goto('./transfer');
    await page.getByRole('textbox').fill('a'.repeat(22));
    await page.getByRole('button', { name: '恢复到这台设备' }).click();
    if (scenario === 'invalid-code') {
      await expect(page.getByText('恢复码无效，请检查后重试。')).toBeVisible();
      await expect(page.getByText('身份恢复成功，正在进入友间。')).toHaveCount(
        0,
      );
      expect(membershipRequests).toBe(0);
    } else {
      if (scenario === 'membership-retry') {
        await expect(
          page.getByText('身份恢复成功，正在进入友间。'),
        ).toBeVisible();
        await expect(
          page.getByText('暂时无法进入友间，请重试进入，无需再次兑换恢复码。'),
        ).toBeVisible();
        await page.screenshot({
          path: testInfo.outputPath('recovery-success-retry.png'),
          fullPage: true,
        });
        await page
          .getByRole('button', { name: '进入友间', exact: true })
          .click();
      }
      await expect(page).toHaveURL(new RegExp(`/space/${spaceId}$`));
      await expect(
        page.getByText('JJJJ', { exact: true }).first(),
      ).toBeVisible();
      await expect(
        page.getByText('这个恢复码已经使用过，请换一个。'),
      ).toHaveCount(0);
    }
    expect(redeemed).toBe(1);
    await page.screenshot({
      path: testInfo.outputPath(`${scenario}.png`),
      fullPage: true,
    });
  });
}
