import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from '@playwright/test';
import {
  anonymousClient,
  cleanupAchievementFixture,
  randomKey,
  rpc,
  setFocusClock,
  superuserSql,
} from './achievement-fixture.mjs';

const decisiveTitle = '\u4e00\u9524\u5b9a\u97f3';
const sharedTitle = '\u5929\u6daf\u5171\u6b64\u65f6';
const defaultBaseUrl = 'http://127.0.0.1:4173';

async function waitForPreview(baseUrl) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(baseUrl);
      if (response.ok) return;
    } catch {
      // Vite preview is still starting.
    }
    await delay(250);
  }
  throw new Error(`Preview server did not become ready at ${baseUrl}`);
}

async function main() {
  const owner = await anonymousClient();
  const created = await rpc(owner.supabase, 'create_space', {
    p_display_name: `e2e-owner-${randomKey().slice(0, 6)}`,
    p_space_name: `achievement-e2e-${randomKey().slice(0, 8)}`,
    p_space_timezone: 'Asia/Shanghai',
    p_profile_timezone: 'Asia/Shanghai',
    p_member_limit: 4,
    p_idempotency_key: randomKey(),
  });
  assert.equal(created.ok, true, 'fixture space creation succeeds');
  const spaceId = created.data.space.id;

  const started = await rpc(owner.supabase, 'start_focus', {
    p_space_id: spaceId,
    p_task_name: '一锤定音 E2E',
    p_category: 'study',
    p_idempotency_key: randomKey(),
  });
  assert.equal(started.ok, true, 'production start_focus path succeeds');
  const sessionId = started.data.session.session_id;

  // The fixture advances the durable session clock without waiting. The end
  // command itself remains the production settlement path.
  setFocusClock(sessionId, new Date(Date.now() - 65 * 60_000));
  const ended = await rpc(owner.supabase, 'end_focus', {
    p_session_id: sessionId,
    p_idempotency_key: randomKey(),
  });
  assert.equal(ended.ok, true, 'production end_focus path succeeds');
  assert.equal(ended.data.session.status, 'completed');
  assert.ok(ended.data.session.accumulated_focus_seconds >= 3600);

  const personal = await rpc(owner.supabase, 'list_personal_achievements', {
    p_space_id: spaceId,
    p_limit: 30,
    p_cursor: null,
  });
  assert.equal(personal.ok, true, 'personal achievement RPC succeeds');
  const decisive = personal.data.items.find(
    (item) => item.achievement_type === 'decisive_focus',
  );
  assert.ok(decisive, '一锤定音 is present in the personal card list');
  assert.equal(decisive.card_key, 'decisive_focus');
  assert.equal(decisive.attained_stage, 1);
  assert.equal(decisive.tier, 'gold');
  assert.deepEqual(decisive.read_target, {
    kind: 'personal_tab',
    key: 'personal',
  });

  const home = await rpc(owner.supabase, 'get_home_snapshot', {
    p_space_id: spaceId,
  });
  assert.equal(home.ok, true, 'home snapshot RPC succeeds');
  assert.equal(
    home.data.unseen_personal_achievement.achievement_type,
    'decisive_focus',
  );
  assert.equal(
    home.data.unseen_personal_achievement.read_target.kind,
    'personal_tab',
  );

  // Keep a known shared card alongside an unregistered historical row. The
  // latter must remain readable by the RPC without making the whole shared
  // tab fail its frontend response contract.
  const sharedDedupeKey = `global-timezones-e2e-${randomKey()}`;
  const legacyDedupeKey = `legacy-shared-e2e-${randomKey()}`;
  assert.match(
    superuserSql(
      `insert into public.achievements(
        space_id,achievement_type,dedupe_key,earned_at,metadata,tier,
        participants_recorded,notification_eligible
      ) values(
        '${spaceId}'::uuid,'global_timezones','${sharedDedupeKey}',now(),
        '{"timezone_count":2,"timezones":["Asia/Shanghai","Europe/Berlin"]}'::jsonb,
        'silver',true,true
      ) returning id`,
    ),
    /^[0-9a-f-]{36}$/i,
    'known shared achievement fixture is created',
  );
  assert.match(
    superuserSql(
      `insert into public.achievements(
        space_id,achievement_type,dedupe_key,earned_at,metadata,tier,
        participants_recorded,notification_eligible
      ) values(
        '${spaceId}'::uuid,'legacy_shared_key','${legacyDedupeKey}',now(),
        '{"legacy_payload":{"nested":true}}'::jsonb,
        'bronze',false,true
      ) returning id`,
    ),
    /^[0-9a-f-]{36}$/i,
    'unregistered historical achievement fixture is created',
  );

  // Complete the same production path in a real browser context. The
  // backend fixture only supplies the authenticated session and deterministic
  // data; the page, RPC reads, card rendering, tier class, icon, and tab-read
  // request all go through the built application.
  const baseUrl = process.env.PLAYWRIGHT_BASE_URL ?? defaultBaseUrl;
  let preview;
  let browser;
  try {
    if (!process.env.PLAYWRIGHT_BASE_URL) {
      preview = spawn(
        process.execPath,
        [
          'node_modules/vite/bin/vite.js',
          'preview',
          '--host',
          '127.0.0.1',
          '--port',
          '4173',
          '--strictPort',
        ],
        { cwd: process.cwd(), stdio: 'inherit' },
      );
      await waitForPreview(baseUrl);
    }
    const sessionResult = await owner.supabase.auth.getSession();
    assert.ifError(sessionResult.error);
    assert.ok(sessionResult.data.session, 'fixture has a browser session');
    browser = await chromium.launch({
      headless: true,
      channel:
        process.env.PLAYWRIGHT_CHANNEL ??
        (process.env.CI ? undefined : 'chrome'),
    });
    const context = await browser.newContext({ baseURL: baseUrl });
    await context.addInitScript(
      ({ session }) => {
        localStorage.setItem('sb-127-auth-token', JSON.stringify(session));
      },
      { session: sessionResult.data.session },
    );
    const page = await context.newPage();
    const achievementTabRequests = [];
    page.on('request', (request) => {
      if (request.url().includes('/rest/v1/rpc/')) {
        if (request.url().includes('/rest/v1/rpc/mark_achievement_tab_seen')) {
          achievementTabRequests.push(request.url());
        }
      }
    });
    await page.goto(`/space/${spaceId}/goals`, {
      waitUntil: 'domcontentloaded',
    });
    const card = page
      .locator('article.achievement-card')
      .filter({ hasText: decisiveTitle });
    await card.waitFor({ state: 'visible', timeout: 30_000 });
    assert.match(
      (await card.getAttribute('class')) ?? '',
      /achievement-card--gold/,
      'browser card uses the catalog tier',
    );
    assert.equal(
      await card.locator('svg.lucide-gavel').count(),
      1,
      'browser card renders the selected new icon',
    );
    assert.ok(
      achievementTabRequests.length > 0,
      'personal achievement tab read is sent by the browser',
    );
    await page.getByRole('tab', { name: '\u5171\u540c\u6210\u5c31' }).click();
    const sharedCard = page
      .locator('article.achievement-card')
      .filter({ hasText: sharedTitle });
    await sharedCard.waitFor({ state: 'visible', timeout: 30_000 });
    assert.match(
      (await sharedCard.getAttribute('class')) ?? '',
      /achievement-card--silver/,
      'shared card remains visible with the catalog tier',
    );
    assert.equal(
      await sharedCard.locator('svg.lucide-plane').count(),
      1,
      'shared card renders the selected timezone icon',
    );
    assert.equal(
      await page
        .getByText('\u65e0\u6cd5\u52a0\u8f7d\u6210\u5c31\u8bb0\u5f55', {
          exact: true,
        })
        .count(),
      0,
      'legacy shared metadata does not poison the shared achievement page',
    );
    await context.close();
  } finally {
    await browser?.close();
    preview?.kill();
  }

  assert.equal(
    superuserSql(
      `select count(*) from public.personal_achievement_awards where user_id='${owner.userId}'::uuid and achievement_type='decisive_focus'`,
    ),
    '1',
  );
  assert.equal(
    superuserSql(
      `select count(*) from public.focus_events where session_id='${sessionId}'::uuid and event_type='task_updated'`,
    ),
    '0',
  );
  cleanupAchievementFixture(owner.userId, spaceId);
  process.stdout.write(
    'PASS 一锤定音 production start -> settle -> award -> RPC display path\n',
  );
}

main().catch((error) => {
  process.stderr.write(
    `FAIL achievement decisive-focus E2E: ${error instanceof Error ? error.stack : String(error)}\n`,
  );
  process.exitCode = 1;
});
