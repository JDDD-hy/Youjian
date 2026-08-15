import type { PostgrestError } from '@supabase/supabase-js';
import { getSupabaseClient } from './supabase';

interface RpcSuccess<T> {
  ok: true;
  request_id: string;
  server_now: string;
  data: T;
}

interface RpcFailure {
  ok: false;
  request_id?: string;
  server_now?: string;
  error: { code: string; details?: Record<string, unknown> };
  authoritative_state?: unknown;
}

export type RpcEnvelope<T> = RpcSuccess<T> | RpcFailure;

const messages: Record<string, string> = {
  CROSS_SPACE_RESPONSE: '服务器返回了不属于当前友间的数据，内容已停止显示。',
  REQUEST_TIMEOUT: '请求超过 10 秒仍未完成，请重试。',
  INVITE_INVALID: '这个邀请已失效，请让房主发送新的邀请链接。',
  SPACE_FULL: '这里已经坐满了。',
  DISPLAY_NAME_TAKEN: '这个昵称已有人使用，请换一个。',
  ALREADY_IN_SPACE: '你已经在这个友间里。',
  ALREADY_IN_ANOTHER_SPACE: '当前设备身份已经加入了另一个友间。',
  MEMBER_DISABLED: '你已不能进入这个友间，历史记录仍会保留。',
  INVALID_DISPLAY_NAME: '昵称需要包含 1–20 个字符。',
  INVALID_SPACE_NAME: '友间名称需要包含 1–30 个字符。',
  INVALID_TIMEZONE: '请选择有效的时区。',
  INVALID_DEADLINE_TITLE: '倒数日名称需要包含 1–40 个字。',
  INVALID_DEADLINE_DATE: '倒数日日期不能早于今天。',
  INVALID_MEMBER_LIMIT: '成员上限需要在 2–12 人之间。',
  MEMBER_LIMIT_NOT_INCREASED: '新上限必须高于当前成员上限。',
  GOAL_ALREADY_OPEN: '当前已有待投票、待开始或进行中的共同目标。',
  INVALID_TASK_NAME: '写下这次要做的事情，最多 80 个字符。',
  INVALID_CATEGORY: '请选择有效的分类。',
  INVALID_DAILY_GOAL_SCOPE: '请选择仅修改今天，或从明天起每天重复。',
  INVALID_DAILY_GOAL_TARGET: '每日专注目标需要在 30–720 分钟之间。',
  DAILY_GOAL_LOCKED: '今天已经开始过专注，今日目标不能再修改。',
  SESSION_ALREADY_ACTIVE: '你已有一段专注正在进行，正在同步最新状态。',
  SESSION_NOT_ACTIVE: '这段专注已不再进行，正在同步最新状态。',
  SESSION_NOT_FOCUSING: '这段专注当前无法暂停，正在同步最新状态。',
  SESSION_NOT_PAUSED: '这段专注当前无法恢复，正在同步最新状态。',
  VOTE_ALREADY_FINAL: '你的投票已提交，不能更改。',
  NOT_ENOUGH_MEMBERS: '至少需要两名成员才能创建共同目标。',
  NOT_SPACE_OWNER: '只有房主可以执行这个操作。',
  CANNOT_DISABLE_OWNER: '不能停用房主。',
  MEMBER_ALREADY_DISABLED: '这位成员已经停用。',
  OWNER_MUST_TRANSFER_OR_DISSOLVE: '房主需要先转让房主，或解散友间。',
  CANNOT_TRANSFER_TO_SELF: '不能把房主转让给自己。',
  MEMBER_NOT_FOUND: '没有找到这位成员。',
  INVALID_TRANSFER_CODE: '迁移码无效，请检查后重试。',
  TRANSFER_CODE_USED: '这个迁移码已经使用过，请在原设备重新生成。',
  TRANSFER_CODE_EXPIRED: '迁移码已过期，请在原设备重新生成。',
  INVALID_RECOVERY_CODE: '恢复码无效，请检查后重试。',
  RECOVERY_CODE_USED: '这个恢复码已经使用过，请换一个。',
  TARGET_IDENTITY_NOT_EMPTY:
    '当前设备已有使用记录，不能覆盖；请先退出当前设备后重试。',
  NETWORK_UNCONFIRMED: '连接状态不可确认，这次操作尚未生效。',
  IDEMPOTENCY_KEY_REUSED: '请求标识已用于其他操作，请重新提交。',
  HEALTH_POLICY_ACK_REQUIRED: '请先阅读并确认两小时健康检查规则。',
  INVALID_POLICY_VERSION: '健康检查规则版本无效，请刷新后重试。',
  CLIENT_UPDATE_REQUIRED: '健康检查规则已更新，请刷新页面后再开始专注。',
  INVALID_HEALTH_CHECK_CHOICE: '请选择结束或继续专注。',
  HEALTH_CHECK_NOT_PENDING: '健康检查状态已更新，正在同步服务器结果。',
};

export class ApiError extends Error {
  constructor(
    public readonly code: string,
    public readonly requestId?: string,
    public readonly authoritativeState?: unknown,
  ) {
    super(messages[code] ?? '暂时无法完成操作，请稍后重试。');
    this.name = 'ApiError';
  }
}

function transportError(error: PostgrestError | null): ApiError {
  return new ApiError(error ? 'TRANSPORT_ERROR' : 'INVALID_RESPONSE');
}

export async function rpc<T>(
  name: string,
  params: Record<string, unknown> = {},
): Promise<{ data: T; serverNow: string; requestId: string }> {
  // PostgreSQL function arguments use the p_ prefix while the public contract
  // intentionally exposes plain snake_case field names.
  const databaseParams = Object.fromEntries(
    Object.entries(params).map(([key, value]) => [
      key.startsWith('p_') ? key : `p_${key}`,
      value,
    ]),
  );
  const controller = new AbortController();
  let timeout: number | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeout = window.setTimeout(() => {
      controller.abort();
      reject(new ApiError('REQUEST_TIMEOUT'));
    }, 10_000);
  });
  const result = await Promise.race([
    getSupabaseClient()
      .rpc(name, databaseParams)
      .abortSignal(controller.signal),
    timeoutPromise,
  ]).finally(() => window.clearTimeout(timeout));
  if (result.error) throw transportError(result.error);
  const envelope = result.data as RpcEnvelope<T> | null;
  if (!envelope || typeof envelope !== 'object' || !('ok' in envelope)) {
    throw transportError(null);
  }
  if (!envelope.ok) {
    throw new ApiError(
      envelope.error.code,
      envelope.request_id,
      envelope.authoritative_state,
    );
  }
  return {
    data: envelope.data,
    serverNow: envelope.server_now,
    requestId: envelope.request_id,
  };
}

export async function ensureAnonymousSession(captchaToken?: string) {
  const supabase = getSupabaseClient();
  const { data } = await withRequestTimeout(supabase.auth.getSession());
  if (data.session) return data.session;
  const result = await withRequestTimeout(
    supabase.auth.signInAnonymously(
      captchaToken ? { options: { captchaToken } } : undefined,
    ),
  );
  if (result.error || !result.data.session) {
    throw new ApiError('AUTH_FAILED');
  }
  return result.data.session;
}

export const createIdempotencyKey = () => crypto.randomUUID();

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}

export function withRequestTimeout<T>(request: PromiseLike<T>, ms = 10_000) {
  let timeout: number | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeout = window.setTimeout(
      () => reject(new ApiError('REQUEST_TIMEOUT')),
      ms,
    );
  });
  return Promise.race([Promise.resolve(request), timeoutPromise]).finally(() =>
    window.clearTimeout(timeout),
  );
}
