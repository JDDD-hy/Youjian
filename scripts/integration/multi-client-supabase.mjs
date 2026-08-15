import assert from 'node:assert/strict';
import { execFileSync, execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const assertions = [];
const turnstileTestToken = 'XXXX.DUMMY.TOKEN.XXXX';

function record(label, condition, details = undefined) {
  assert.ok(condition, details ?? label);
  assertions.push(label);
  process.stdout.write(`PASS ${assertions.length}: ${label}\n`);
}

function parseStatus() {
  const raw = execSync('npx supabase status -o env', {
    cwd: process.cwd(),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  const values = new Map();
  for (const line of raw.split(/\r?\n/)) {
    const match = line.match(/^([A-Z_]+)="(.*)"$/);
    if (match) values.set(match[1], match[2]);
  }
  return {
    url: values.get('API_URL'),
    anonKey: values.get('ANON_KEY'),
  };
}

class MemoryStorage {
  #items = new Map();

  getItem(key) {
    return this.#items.get(key) ?? null;
  }

  setItem(key, value) {
    this.#items.set(key, value);
  }

  removeItem(key) {
    this.#items.delete(key);
  }
}

const status = parseStatus();
assert.ok(status.url && status.anonKey, 'Local Supabase status is incomplete');

function client(storage = new MemoryStorage()) {
  return createClient(status.url, status.anonKey, {
    auth: {
      storage,
      persistSession: true,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { headers: { 'x-client-info': 'youjian-multiclient-integration' } },
  });
}

function sql(statement) {
  return execFileSync(
    'docker',
    [
      'exec',
      'supabase_db_youjian',
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-Atqc',
      statement,
    ],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  ).trim();
}

async function anonymous(storage = new MemoryStorage()) {
  const supabase = client(storage);
  const { data, error } = await supabase.auth.signInAnonymously({
    options: { captchaToken: turnstileTestToken },
  });
  assert.ifError(error);
  assert.ok(data.user?.id);
  return { supabase, storage, userId: data.user.id };
}

async function rpc(actor, name, args) {
  const { data, error } = await actor.rpc(name, args);
  assert.ifError(error);
  assert.equal(
    typeof data?.ok,
    'boolean',
    `${name} did not return the API envelope`,
  );
  return data;
}

function ok(result, message) {
  record(message, result.ok === true);
  return result.data;
}

function errorCode(result, expected, message) {
  record(message, result.ok === false && result.error?.code === expected);
}

function tokenFromUrl(url) {
  const token = new URL(url, 'http://localhost').pathname
    .split('/')
    .filter(Boolean)
    .at(-1);
  assert.ok(token && token.length >= 40);
  return token;
}

async function createSpace(actor, memberLimit = 4) {
  return rpc(actor, 'create_space', {
    p_display_name: `owner-${randomUUID().slice(0, 8)}`,
    p_space_name: `space-${randomUUID().slice(0, 8)}`,
    p_space_timezone: 'Asia/Shanghai',
    p_profile_timezone: 'Asia/Shanghai',
    p_member_limit: memberLimit,
    p_idempotency_key: randomUUID(),
  });
}

async function join(actor, token, displayName, key = randomUUID()) {
  return rpc(actor, 'join_space', {
    p_invite_token: token,
    p_display_name: displayName,
    p_profile_timezone: 'Asia/Shanghai',
    p_idempotency_key: key,
  });
}

async function setSessionTiming(sessionId, fields) {
  assert.match(sessionId, /^[0-9a-f-]{36}$/);
  if (fields.pausedAt) {
    const pausedAt = new Date(fields.pausedAt).toISOString();
    sql(
      `update public.focus_sessions set paused_at='${pausedAt}'::timestamptz where id='${sessionId}'::uuid`,
    );
  }
  if (fields.activeStartedAt) {
    const activeAt = new Date(fields.activeStartedAt).toISOString();
    sql(
      `update public.focus_sessions set active_segment_started_at='${activeAt}'::timestamptz,started_at='${activeAt}'::timestamptz,last_seen_at='${activeAt}'::timestamptz where id='${sessionId}'::uuid`,
    );
    sql(
      `update public.focus_segments set started_at='${activeAt}'::timestamptz where session_id='${sessionId}'::uuid and ended_at is null`,
    );
  }
}

async function runMaintenance() {
  return sql('select public.run_minute_maintenance()');
}

async function main() {
  const missingCaptcha = await client().auth.signInAnonymously();
  record(
    'anonymous auth rejects a missing CAPTCHA token',
    Boolean(missingCaptcha.error) && !missingCaptcha.data.user,
  );
  const ownerStorage = new MemoryStorage();
  const owner = await anonymous(ownerStorage);
  const created = ok(
    await createSpace(owner.supabase, 4),
    'owner can create a room',
  );
  const spaceId = created.space.id;
  const ownerMemberId = created.membership.member_id;
  const originalToken = tokenFromUrl(created.invite.invite_url);

  const memberOneStorage = new MemoryStorage();
  const memberOne = await anonymous(memberOneStorage);
  const memberOneJoin = ok(
    await join(
      memberOne.supabase,
      originalToken,
      `member-${randomUUID().slice(0, 8)}`,
    ),
    'second anonymous client can join through invite',
  );

  const restoredMember = client(memberOneStorage);
  const restoredSession = await restoredMember.auth.getSession();
  assert.ifError(restoredSession.error);
  record(
    'anonymous identity survives client recreation',
    restoredSession.data.session?.user.id === memberOne.userId,
  );
  const restoredMembership = ok(
    await rpc(restoredMember, 'get_my_membership', {}),
    'restored client can recover membership',
  );
  record(
    'restored membership is the original membership',
    restoredMembership.membership.member_id ===
      memberOneJoin.membership.member_id,
  );

  const rotated = ok(
    await rpc(owner.supabase, 'rotate_invite', {
      p_space_id: spaceId,
      p_idempotency_key: randomUUID(),
    }),
    'owner can rotate invite token',
  );
  const rotatedToken = tokenFromUrl(rotated.invite_url);
  errorCode(
    await rpc(client(), 'get_invite_preview', {
      p_invite_token: originalToken,
    }),
    'INVITE_INVALID',
    'rotated invite immediately invalidates the old token',
  );
  ok(
    await rpc(client(), 'get_invite_preview', { p_invite_token: rotatedToken }),
    'rotated invite is valid for preview',
  );

  const memberTwo = await anonymous();
  const memberTwoJoin = ok(
    await join(
      memberTwo.supabase,
      rotatedToken,
      `member-${randomUUID().slice(0, 8)}`,
    ),
    'third anonymous client joins using rotated invite',
  );
  errorCode(
    await join(
      memberOne.supabase,
      rotatedToken,
      `again-${randomUUID().slice(0, 8)}`,
    ),
    'ALREADY_IN_SPACE',
    'an existing member cannot join the same room again with a new command key',
  );
  const invalidTimezoneClient = await anonymous();
  errorCode(
    await rpc(invalidTimezoneClient.supabase, 'join_space', {
      p_invite_token: rotatedToken,
      p_display_name: `timezone-${randomUUID().slice(0, 8)}`,
      p_profile_timezone: 'Mars/Olympus_Mons',
      p_idempotency_key: randomUUID(),
    }),
    'INVALID_TIMEZONE',
    'join rejects an invalid profile timezone',
  );

  const ownerSettings = ok(
    await rpc(owner.supabase, 'get_space_settings', { p_space_id: spaceId }),
    'owner can read room settings',
  );
  const memberSettings = ok(
    await rpc(memberOne.supabase, 'get_space_settings', {
      p_space_id: spaceId,
    }),
    'member can read room settings',
  );
  record(
    'owner receives owner-only settings capabilities',
    ownerSettings.owner_actions.can_rotate_invite === true,
  );
  record(
    'member receives no owner-only settings capabilities',
    memberSettings.owner_actions.can_rotate_invite === false,
  );
  errorCode(
    await rpc(memberOne.supabase, 'rotate_invite', {
      p_space_id: spaceId,
      p_idempotency_key: randomUUID(),
    }),
    'NOT_SPACE_OWNER',
    'member cannot rotate invite token',
  );
  errorCode(
    await rpc(memberOne.supabase, 'disable_member', {
      p_space_id: spaceId,
      p_member_id: ownerMemberId,
      p_idempotency_key: randomUUID(),
    }),
    'NOT_SPACE_OWNER',
    'member cannot disable another member',
  );

  const slotOwner = await anonymous();
  const slotCreated = ok(
    await createSpace(slotOwner.supabase, 2),
    'final-slot fixture room is created',
  );
  const slotToken = tokenFromUrl(slotCreated.invite.invite_url);
  const slotCandidateA = await anonymous();
  const slotCandidateB = await anonymous();
  const slotResults = await Promise.all([
    join(
      slotCandidateA.supabase,
      slotToken,
      `candidate-${randomUUID().slice(0, 8)}`,
    ),
    join(
      slotCandidateB.supabase,
      slotToken,
      `candidate-${randomUUID().slice(0, 8)}`,
    ),
  ]);
  record(
    'concurrent final-slot join admits exactly one client',
    slotResults.filter((x) => x.ok).length === 1,
  );
  record(
    'concurrent final-slot loser receives SPACE_FULL',
    slotResults.filter((x) => !x.ok && x.error?.code === 'SPACE_FULL')
      .length === 1,
  );

  const nicknameOwner = await anonymous();
  const nicknameCreated = ok(
    await createSpace(nicknameOwner.supabase, 3),
    'nickname-race fixture room is created',
  );
  const nicknameToken = tokenFromUrl(nicknameCreated.invite.invite_url);
  const nicknameCandidateA = await anonymous();
  const nicknameCandidateB = await anonymous();
  const nicknameRoot = `alias-${randomUUID().slice(0, 8)}`;
  const nicknameResults = await Promise.all([
    join(
      nicknameCandidateA.supabase,
      nicknameToken,
      nicknameRoot.toUpperCase(),
    ),
    join(
      nicknameCandidateB.supabase,
      nicknameToken,
      `  ${nicknameRoot.toLowerCase()}  `,
    ),
  ]);
  record(
    'normalized nickname race admits exactly one client',
    nicknameResults.filter((x) => x.ok).length === 1,
  );
  record(
    'normalized nickname race loser receives DISPLAY_NAME_TAKEN',
    nicknameResults.filter(
      (x) => !x.ok && x.error?.code === 'DISPLAY_NAME_TAKEN',
    ).length === 1,
  );

  const distinctStarts = await Promise.all([
    rpc(owner.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: `focus-${randomUUID().slice(0, 8)}`,
      p_category: 'study',
      p_idempotency_key: randomUUID(),
    }),
    rpc(owner.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: `focus-${randomUUID().slice(0, 8)}`,
      p_category: 'work',
      p_idempotency_key: randomUUID(),
    }),
  ]);
  record(
    'concurrent distinct-key starts create exactly one active session',
    distinctStarts.filter((x) => x.ok).length === 1,
  );
  record(
    'concurrent distinct-key start loser receives SESSION_ALREADY_ACTIVE',
    distinctStarts.filter(
      (x) => !x.ok && x.error?.code === 'SESSION_ALREADY_ACTIVE',
    ).length === 1,
  );
  const ownerSessionId = distinctStarts.find((x) => x.ok).data.session
    .session_id;

  errorCode(
    await rpc(memberOne.supabase, 'pause_focus', {
      p_session_id: ownerSessionId,
      p_idempotency_key: randomUUID(),
    }),
    'SESSION_NOT_FOUND',
    'another room member cannot mutate the owner session',
  );
  const outsider = await anonymous();
  const outsiderRoom = ok(
    await createSpace(outsider.supabase, 2),
    'cross-room fixture room is created',
  );
  const outsiderVisible = await outsider.supabase
    .from('focus_sessions')
    .select('id')
    .eq('id', ownerSessionId);
  assert.ifError(outsiderVisible.error);
  record(
    'RLS hides session rows from a user in another room',
    outsiderVisible.data.length === 0 && outsiderRoom.space.id !== spaceId,
  );

  const pauses = await Promise.all([
    rpc(owner.supabase, 'pause_focus', {
      p_session_id: ownerSessionId,
      p_idempotency_key: randomUUID(),
    }),
    rpc(owner.supabase, 'pause_focus', {
      p_session_id: ownerSessionId,
      p_idempotency_key: randomUUID(),
    }),
  ]);
  record(
    'concurrent pause produces exactly one state transition',
    pauses.filter((x) => x.ok).length === 1,
  );
  record(
    'concurrent pause loser receives SESSION_NOT_FOCUSING',
    pauses.filter((x) => !x.ok && x.error?.code === 'SESSION_NOT_FOCUSING')
      .length === 1,
  );
  await rpc(owner.supabase, 'end_focus', {
    p_session_id: ownerSessionId,
    p_idempotency_key: randomUUID(),
  });

  const retryKey = randomUUID();
  const sameKeyStarts = await Promise.all([
    rpc(memberOne.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: 'idempotency-check',
      p_category: 'study',
      p_idempotency_key: retryKey,
    }),
    rpc(memberOne.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: 'idempotency-check',
      p_category: 'study',
      p_idempotency_key: retryKey,
    }),
  ]);
  record(
    'same-key concurrent start retries both succeed',
    sameKeyStarts.every((x) => x.ok),
  );
  const retrySessionId = sameKeyStarts[0].data.session.session_id;
  record(
    'same-key concurrent start returns the same session',
    sameKeyStarts.every((x) => x.data.session.session_id === retrySessionId),
  );
  const retrySessionRows = await memberOne.supabase
    .from('focus_sessions')
    .select('id')
    .eq('id', retrySessionId);
  assert.ifError(retrySessionRows.error);
  record(
    'same-key retry persists only one session row',
    retrySessionRows.data.length === 1,
  );

  ok(
    await rpc(memberOne.supabase, 'pause_focus', {
      p_session_id: retrySessionId,
      p_idempotency_key: randomUUID(),
    }),
    'timeout-race fixture session is paused',
  );
  await setSessionTiming(retrySessionId, {
    pausedAt: new Date(Date.now() - 16 * 60_000).toISOString(),
  });
  const [resumeResult] = await Promise.all([
    rpc(memberOne.supabase, 'resume_focus', {
      p_session_id: retrySessionId,
      p_idempotency_key: randomUUID(),
    }),
    runMaintenance(),
  ]);
  record(
    'resume versus timeout maintenance converges without transport failure',
    typeof resumeResult.ok === 'boolean',
  );
  const timeoutFinal = await memberOne.supabase
    .from('focus_sessions')
    .select('status,completion_reason')
    .eq('id', retrySessionId)
    .single();
  assert.ifError(timeoutFinal.error);
  record(
    'resume versus timeout maintenance converges to a settled pause_timeout session',
    ['completed', 'discarded'].includes(timeoutFinal.data.status) &&
      timeoutFinal.data.completion_reason === 'pause_timeout',
  );

  const endRaceStart = ok(
    await rpc(memberTwo.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: 'focus-limit-race',
      p_category: 'work',
      p_idempotency_key: randomUUID(),
    }),
    'focus-limit race fixture session starts',
  );
  const endRaceSessionId = endRaceStart.session.session_id;
  await setSessionTiming(endRaceSessionId, {
    activeStartedAt: new Date(Date.now() - (4 * 60 + 1) * 60_000).toISOString(),
  });
  const [endRaceResult] = await Promise.all([
    rpc(memberTwo.supabase, 'end_focus', {
      p_session_id: endRaceSessionId,
      p_idempotency_key: randomUUID(),
    }),
    runMaintenance(),
  ]);
  record(
    'manual end versus maintenance converges without transport failure',
    endRaceResult.ok === true,
  );
  const endRaceFinal = await memberTwo.supabase
    .from('focus_sessions')
    .select('status,completion_reason,accumulated_focus_seconds')
    .eq('id', endRaceSessionId)
    .single();
  assert.ifError(endRaceFinal.error);
  record(
    'manual end versus maintenance caps duration and settles exactly once',
    endRaceFinal.data.status === 'completed' &&
      endRaceFinal.data.completion_reason === 'focus_limit' &&
      endRaceFinal.data.accumulated_focus_seconds === 14400,
  );
  const completionEvents = await memberTwo.supabase
    .from('focus_events')
    .select('id', { count: 'exact', head: true })
    .eq('session_id', endRaceSessionId)
    .eq('event_type', 'completed');
  assert.ifError(completionEvents.error);
  record(
    'end versus maintenance records exactly one completion event',
    completionEvents.count === 1,
  );

  const oppositeStart = ok(
    await rpc(memberOne.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: 'opposite-tab-race',
      p_category: 'study',
      p_idempotency_key: randomUUID(),
    }),
    'opposite-operation race fixture starts',
  );
  const oppositeSessionId = oppositeStart.session.session_id;
  const [oppositePause, oppositeResume] = await Promise.all([
    rpc(memberOne.supabase, 'pause_focus', {
      p_session_id: oppositeSessionId,
      p_idempotency_key: randomUUID(),
    }),
    rpc(memberOne.supabase, 'resume_focus', {
      p_session_id: oppositeSessionId,
      p_idempotency_key: randomUUID(),
    }),
  ]);
  record(
    'opposite tab operations return authoritative envelopes without transport failure',
    oppositePause.ok === true && typeof oppositeResume.ok === 'boolean',
  );
  const oppositeFinal = await memberOne.supabase
    .from('focus_sessions')
    .select('status')
    .eq('id', oppositeSessionId)
    .single();
  assert.ifError(oppositeFinal.error);
  record(
    'opposite tab operations converge to one valid state',
    ['focusing', 'paused'].includes(oppositeFinal.data.status),
  );
  ok(
    await rpc(memberOne.supabase, 'end_focus', {
      p_session_id: oppositeSessionId,
      p_idempotency_key: randomUUID(),
    }),
    'opposite-operation fixture can be authoritatively settled',
  );

  const proposal = ok(
    await rpc(owner.supabase, 'propose_goal', {
      p_space_id: spaceId,
      p_goal_type: 'group_total_minutes',
      p_period_type: 'weekly',
      p_target_value: 60,
      p_idempotency_key: randomUUID(),
    }),
    'active member can propose a shared goal',
  );
  const proposalId = proposal.proposal.proposal_id;
  const votes = await Promise.all([
    rpc(memberOne.supabase, 'vote_goal_proposal', {
      p_proposal_id: proposalId,
      p_vote: 'accepted',
      p_idempotency_key: randomUUID(),
    }),
    rpc(memberTwo.supabase, 'vote_goal_proposal', {
      p_proposal_id: proposalId,
      p_vote: 'accepted',
      p_idempotency_key: randomUUID(),
    }),
  ]);
  record(
    'concurrent final voters both commit accepted votes',
    votes.every((x) => x.ok),
  );
  const goalRows = await owner.supabase
    .from('goals')
    .select('id')
    .eq('source_proposal_id', proposalId);
  assert.ifError(goalRows.error);
  record(
    'concurrent final voting creates exactly one scheduled goal',
    goalRows.data.length === 1,
  );
  const proposalRow = await owner.supabase
    .from('goal_proposals')
    .select('status')
    .eq('id', proposalId)
    .single();
  assert.ifError(proposalRow.error);
  record(
    'concurrent unanimous voting leaves proposal accepted',
    proposalRow.data.status === 'accepted',
  );

  const achievementId = sql(
    `insert into public.achievements(space_id,achievement_type,dedupe_key) values('${spaceId}'::uuid,'integration','integration-${randomUUID()}') returning id`,
  ).split(/\r?\n/)[0];
  assert.match(achievementId, /^[0-9a-f-]{36}$/);
  const initialAchievements = ok(
    await rpc(memberOne.supabase, 'list_achievements', {
      p_space_id: spaceId,
      p_limit: 30,
      p_cursor: null,
    }),
    'member can list room achievements',
  );
  record(
    'new achievement is initially unseen',
    initialAchievements.items.find((x) => x.achievement_id === achievementId)
      ?.seen === false,
  );
  ok(
    await rpc(memberOne.supabase, 'mark_achievement_seen', {
      p_achievement_id: achievementId,
      p_idempotency_key: randomUUID(),
    }),
    'one member can mark an achievement seen',
  );
  const [ownerAchievements, memberOneAchievements, memberTwoAchievements] =
    await Promise.all([
      rpc(owner.supabase, 'list_achievements', {
        p_space_id: spaceId,
        p_limit: 30,
        p_cursor: null,
      }),
      rpc(memberOne.supabase, 'list_achievements', {
        p_space_id: spaceId,
        p_limit: 30,
        p_cursor: null,
      }),
      rpc(memberTwo.supabase, 'list_achievements', {
        p_space_id: spaceId,
        p_limit: 30,
        p_cursor: null,
      }),
    ]);
  const seen = (result) =>
    result.data.items.find((x) => x.achievement_id === achievementId)?.seen;
  record(
    'achievement read state is independent per member',
    seen(ownerAchievements) === false &&
      seen(memberOneAchievements) === true &&
      seen(memberTwoAchievements) === false,
  );

  const disableRaceStart = ok(
    await rpc(memberTwo.supabase, 'start_focus', {
      p_space_id: spaceId,
      p_task_name: 'disable-end-race',
      p_category: 'work',
      p_idempotency_key: randomUUID(),
    }),
    'disable versus end race fixture starts',
  );
  const disableRaceSessionId = disableRaceStart.session.session_id;
  const [disableRace, memberEndRace] = await Promise.all([
    rpc(owner.supabase, 'disable_member', {
      p_space_id: spaceId,
      p_member_id: memberTwoJoin.membership.member_id,
      p_idempotency_key: randomUUID(),
    }),
    rpc(memberTwo.supabase, 'end_focus', {
      p_session_id: disableRaceSessionId,
      p_idempotency_key: randomUUID(),
    }),
  ]);
  record(
    'disable member versus active end converges without transport failure',
    disableRace.ok === true && typeof memberEndRace.ok === 'boolean',
  );
  const disableRaceFinal = sql(
    `select status||'|'||completion_reason from public.focus_sessions where id='${disableRaceSessionId}'::uuid`,
  );
  record(
    'disable member versus end leaves exactly one final session state',
    /^(completed|discarded)\|(manual_end|member_disabled)$/.test(
      disableRaceFinal,
    ),
  );
  const disableCompletionEvents = Number(
    sql(
      `select count(*) from public.focus_events where session_id='${disableRaceSessionId}'::uuid and event_type='completed'`,
    ),
  );
  record(
    'disable member versus end records exactly one completion event',
    disableCompletionEvents === 1,
  );
  errorCode(
    await rpc(memberTwo.supabase, 'get_space_settings', {
      p_space_id: spaceId,
    }),
    'SPACE_ACCESS_DENIED',
    'disabled member immediately loses settings access',
  );
  const settingsAfterDisable = ok(
    await rpc(owner.supabase, 'get_space_settings', { p_space_id: spaceId }),
    'owner retains settings access after disabling a member',
  );
  record(
    'owner settings show the disabled member state',
    settingsAfterDisable.members.some(
      (member) =>
        member.member_id === memberTwoJoin.membership.member_id &&
        member.status === 'disabled',
    ),
  );
  errorCode(
    await join(
      memberTwo.supabase,
      rotatedToken,
      `disabled-${randomUUID().slice(0, 8)}`,
    ),
    'MEMBER_DISABLED',
    'disabled member cannot regain access with the old invite token',
  );

  process.stdout.write(
    `\nAll ${assertions.length} multi-client assertions passed.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(
    `FAIL: ${error instanceof Error ? error.message : 'Unknown integration failure'}\n`,
  );
  process.exitCode = 1;
});
