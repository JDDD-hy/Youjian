import assert from 'node:assert/strict';
import { execFileSync, execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const localCaptchaToken = 'XXXX.DUMMY.TOKEN.XXXX';

export class MemoryStorage {
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

function localStatus() {
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
  assert.ok(values.get('API_URL') && values.get('ANON_KEY'));
  return { url: values.get('API_URL'), anonKey: values.get('ANON_KEY') };
}

const status = localStatus();

export function localClient(storage = new MemoryStorage()) {
  return createClient(status.url, status.anonKey, {
    auth: {
      storage,
      persistSession: true,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { headers: { 'x-client-info': 'youjian-achievement-fixture' } },
  });
}

export async function anonymousClient(storage = new MemoryStorage()) {
  const supabase = localClient(storage);
  const { data, error } = await supabase.auth.signInAnonymously({
    options: { captchaToken: localCaptchaToken },
  });
  assert.ifError(error);
  assert.ok(data.user?.id);
  return { supabase, storage, userId: data.user.id };
}

export async function rpc(actor, name, args) {
  const { data, error } = await actor.rpc(name, args);
  assert.ifError(error);
  assert.equal(typeof data?.ok, 'boolean', `${name} returned no API envelope`);
  return data;
}

export function superuserSql(statement) {
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

export function cleanupAchievementFixture(userId, spaceId) {
  assert.match(userId, /^[0-9a-f-]{36}$/i);
  assert.match(spaceId, /^[0-9a-f-]{36}$/i);
  superuserSql(`
    begin;
    delete from public.achievement_reads
      where member_id in (select id from public.space_members where space_id='${spaceId}'::uuid);
    delete from public.achievement_participants
      where member_id in (select id from public.space_members where space_id='${spaceId}'::uuid);
    delete from public.achievements where space_id='${spaceId}'::uuid;
    delete from public.personal_achievement_awards
      where user_id='${userId}'::uuid or source_space_id='${spaceId}'::uuid;
    delete from public.personal_achievements where user_id='${userId}'::uuid;
    delete from public.achievement_nav_reads
      where member_id in (select id from public.space_members where space_id='${spaceId}'::uuid);
    delete from private.health_check_result_reads
      where user_id='${userId}'::uuid
         or session_id in (select id from public.focus_sessions where space_id='${spaceId}'::uuid);
    delete from public.focus_commands
      where actor_id='${userId}'::uuid
         or session_id in (select id from public.focus_sessions where space_id='${spaceId}'::uuid);
    delete from public.focus_connection_intervals
      where session_id in (select id from public.focus_sessions where space_id='${spaceId}'::uuid);
    alter table public.focus_events disable trigger focus_events_are_append_only;
    alter table public.focus_segments disable trigger closed_focus_segments_are_immutable;
    alter table public.focus_sessions disable trigger settled_focus_sessions_are_immutable;
    delete from public.focus_events
      where session_id in (select id from public.focus_sessions where space_id='${spaceId}'::uuid);
    delete from public.focus_segments
      where session_id in (select id from public.focus_sessions where space_id='${spaceId}'::uuid);
    delete from public.focus_sessions where space_id='${spaceId}'::uuid;
    alter table public.focus_segments enable trigger closed_focus_segments_are_immutable;
    alter table public.focus_events enable trigger focus_events_are_append_only;
    alter table public.focus_sessions enable trigger settled_focus_sessions_are_immutable;
    delete from public.goal_participants
      where member_id in (select id from public.space_members where space_id='${spaceId}'::uuid);
    delete from public.goals where space_id='${spaceId}'::uuid;
    delete from public.goal_proposal_members
      where member_id in (select id from public.space_members where space_id='${spaceId}'::uuid);
    delete from public.goal_proposals where space_id='${spaceId}'::uuid;
    delete from public.personal_focus_goal_defaults where user_id='${userId}'::uuid;
    delete from public.personal_focus_goal_overrides where user_id='${userId}'::uuid;
    delete from private.identity_binding_events
      where principal_user_id='${userId}'::uuid
         or previous_auth_user_id='${userId}'::uuid
         or new_auth_user_id='${userId}'::uuid;
    delete from private.identity_transfer_codes where principal_user_id='${userId}'::uuid;
    delete from private.identity_recovery_codes where principal_user_id='${userId}'::uuid;
    delete from private.identity_bindings
      where auth_user_id='${userId}'::uuid or principal_user_id='${userId}'::uuid;
    delete from public.space_members where space_id='${spaceId}'::uuid;
    delete from public.spaces where id='${spaceId}'::uuid;
    delete from auth.users where id='${userId}'::uuid;
    commit;
  `);
}

export function setFocusClock(sessionId, startedAt) {
  assert.match(sessionId, /^[0-9a-f-]{36}$/i);
  const timestamp = new Date(startedAt).toISOString();
  superuserSql(
    `update public.focus_sessions set active_segment_started_at='${timestamp}'::timestamptz,last_seen_at='${timestamp}'::timestamptz where id='${sessionId}'::uuid`,
  );
  superuserSql(
    `update public.focus_segments set started_at='${timestamp}'::timestamptz where session_id='${sessionId}'::uuid and ended_at is null`,
  );
}

export function randomKey() {
  return randomUUID();
}
