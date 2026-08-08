import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import type { Membership, SpaceSummary } from '../domain/types';
import { ensureAnonymousSession, isApiError, rpc } from '../lib/api';
import { getDeviceTimezone } from '../lib/format';
import { cacheActiveMembership, loadMembership } from '../lib/membership';
import { EmptyState, ErrorState, PageLoader } from '../components/AsyncState';
import { Icon } from '../components/Icons';
import { TurnstileField } from '../components/TurnstileField';
import { useIntentKey } from '../hooks/useIntentKey';
import { useOnlineStatus } from '../hooks/useOnlineStatus';
import { pendingDisplayNameKey } from './JoinWaitingPage';
import {
  downloadRecoveryCodes,
  rotateRecoveryCodes,
} from '../lib/recoveryCodes';

interface InvitePreview {
  status: 'valid' | 'full';
  space_name: string;
  owner_display_name: string;
  active_member_count: number;
  member_limit: number;
  space_timezone: string;
}

export function InvitePage() {
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [displayName, setDisplayName] = useState(
    () => localStorage.getItem(pendingDisplayNameKey) ?? '',
  );
  const [fieldError, setFieldError] = useState('');
  const [terminalError, setTerminalError] = useState<{
    code: string;
    spaceId?: string;
  }>();
  const [captchaToken, setCaptchaToken] = useState<string>();
  const intent = useIntentKey();
  const online = useOnlineStatus();
  const preview = useQuery({
    queryKey: ['invite', token],
    queryFn: () =>
      rpc<InvitePreview>('get_invite_preview', { invite_token: token }),
    retry: false,
  });
  const join = useMutation({
    mutationFn: async () => {
      const value = displayName.trim();
      if (!value || value.length > 20)
        throw new Error('昵称需要包含 1–20 个字符。');
      await ensureAnonymousSession(captchaToken);
      const joined = await rpc<{ space: SpaceSummary; membership: Membership }>(
        'join_space',
        {
          invite_token: token,
          display_name: value,
          profile_timezone: getDeviceTimezone(),
          idempotency_key: intent.get(`${token}:${value}`),
        },
      );
      const recovery = await rotateRecoveryCodes();
      return { joined, recovery };
    },
    onSuccess: ({ joined: { data }, recovery }) => {
      intent.clear();
      localStorage.removeItem(pendingDisplayNameKey);
      cacheActiveMembership(queryClient, {
        ...data.membership,
        space_id: data.space.id,
      });
      downloadRecoveryCodes(
        recovery.data.codes,
        data.membership.display_name,
        recovery.data.generated_at,
      );
      void navigate(`/space/${data.space.id}`, { replace: true });
    },
    onError: async (error) => {
      if (isApiError(error) && error.code === 'DISPLAY_NAME_TAKEN') {
        setFieldError(error.message);
        return;
      }
      if (
        isApiError(error) &&
        [
          'INVITE_INVALID',
          'SPACE_FULL',
          'ALREADY_IN_SPACE',
          'ALREADY_IN_ANOTHER_SPACE',
          'MEMBER_DISABLED',
        ].includes(error.code)
      ) {
        let spaceId: string | undefined;
        if (
          error.code === 'ALREADY_IN_SPACE' ||
          error.code === 'ALREADY_IN_ANOTHER_SPACE'
        ) {
          const membership = await queryClient
            .fetchQuery({
              queryKey: ['membership'],
              queryFn: loadMembership,
              staleTime: 0,
            })
            .catch(() => null);
          spaceId = membership?.membership?.space_id;
        }
        setTerminalError({ code: error.code, spaceId });
      }
    },
  });
  if (preview.isLoading)
    return (
      <main className="form-page">
        <section className="form-card">
          <PageLoader />
        </section>
      </main>
    );
  if (preview.error) {
    const invalid =
      isApiError(preview.error) && preview.error.code === 'INVITE_INVALID';
    return (
      <main className="form-page">
        <section className="form-card">
          {invalid ? (
            <EmptyState title="这个邀请已失效">
              <p>请让房主发送新的邀请链接。</p>
              <Link className="button button--secondary" to="/">
                返回欢迎页
              </Link>
            </EmptyState>
          ) : (
            <ErrorState onRetry={() => void preview.refetch()} />
          )}
        </section>
      </main>
    );
  }
  const info = preview.data!.data;
  if (terminalError) {
    const titles: Record<string, string> = {
      INVITE_INVALID: '这个邀请已失效',
      SPACE_FULL: '这里已经坐满了',
      ALREADY_IN_SPACE: '你已经在这个友间里',
      ALREADY_IN_ANOTHER_SPACE: '这台设备已有友间',
      MEMBER_DISABLED: '成员身份已停用',
    };
    const messages: Record<string, string> = {
      INVITE_INVALID: '请让房主发送新的邀请链接。',
      SPACE_FULL: '当前人数已达到房主设置的上限。',
      ALREADY_IN_SPACE: '无需重复加入，可以直接回到友间。',
      ALREADY_IN_ANOTHER_SPACE: '一个匿名身份只能加入一个友间。',
      MEMBER_DISABLED: '你已不能再次进入这个友间，历史记录仍会保留。',
    };
    return (
      <main className="form-page">
        <section className="form-card">
          <EmptyState title={titles[terminalError.code] ?? '无法加入友间'}>
            <p>{messages[terminalError.code] ?? '请返回欢迎页后重试。'}</p>
            <Link
              className="button button--secondary"
              to={
                terminalError.spaceId ? `/space/${terminalError.spaceId}` : '/'
              }
            >
              {terminalError.spaceId ? '回到我的友间' : '返回欢迎页'}
            </Link>
          </EmptyState>
        </section>
      </main>
    );
  }
  if (info.status === 'full')
    return (
      <main className="form-page">
        <section className="form-card">
          <EmptyState icon="people" title="这里已经坐满了">
            <p>当前人数已达到房主设置的上限。</p>
            <Link className="button button--secondary" to="/">
              返回欢迎页
            </Link>
          </EmptyState>
        </section>
      </main>
    );
  return (
    <main className="form-page">
      <section className="form-card" aria-labelledby="join-title">
        <Link className="back-link" to="/">
          <Icon name="arrow-left" />
          返回
        </Link>
        <p className="eyebrow">来自 {info.owner_display_name} 的邀请</p>
        <h1 id="join-title">加入「{info.space_name}」</h1>
        <div className="invite-meta">
          <span>
            <Icon name="people" />
            {info.active_member_count} / {info.member_limit} 人
          </span>
          <span>
            <Icon name="clock" />
            {info.space_timezone}
          </span>
        </div>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            setFieldError('');
            join.mutate();
          }}
          noValidate
        >
          <label className="field">
            <span>你在这里使用的昵称</span>
            <input
              autoFocus
              autoComplete="nickname"
              maxLength={20}
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              aria-invalid={Boolean(fieldError)}
            />
            {fieldError && <small className="field-error">{fieldError}</small>}
          </label>
          <p className="identity-explainer">
            身份只保存在当前设备；清除浏览器数据或更换设备后无法恢复。
          </p>
          <TurnstileField onToken={setCaptchaToken} />
          {join.error && !fieldError && (
            <div className="inline-notice inline-notice--error" role="alert">
              {join.error.message}
            </div>
          )}
          <button
            className="button button--primary button--full"
            disabled={join.isPending || !online}
          >
            {join.isPending ? '正在为你留座…' : '加入友间'}
          </button>
        </form>
      </section>
    </main>
  );
}
