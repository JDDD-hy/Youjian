import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, useSyncExternalStore } from 'react';
import { useParams } from 'react-router-dom';
import type { SpaceSettings } from '../domain/types';
import { rpc } from '../lib/api';
import { formatLocalDateTime } from '../lib/format';
import { EmptyState, ErrorState, PageLoader } from '../components/AsyncState';
import { Icon } from '../components/Icons';
import { AccessibleModal } from '../components/AccessibleModal';
import { useIntentKey } from '../hooks/useIntentKey';
import packageInfo from '../../package.json';
import {
  getPwaInstallSnapshot,
  promptPwaInstall,
  subscribePwaInstall,
} from '../lib/pwaInstall';
import { assertRouteSpace } from '../lib/spaceBoundary';
import { normalizeInviteUrl } from '../lib/inviteUrl';
import { getSupabaseClient } from '../lib/supabase';

export function SettingsPage() {
  const { spaceId = '' } = useParams();
  const client = useQueryClient();
  const [copied, setCopied] = useState(false);
  const [shared, setShared] = useState(false);
  const [copyError, setCopyError] = useState(false);
  const [installError, setInstallError] = useState(false);
  const [confirmRotate, setConfirmRotate] = useState(false);
  const [confirmExit, setConfirmExit] = useState(false);
  const [exiting, setExiting] = useState(false);
  const [exitError, setExitError] = useState(false);
  const [disableTarget, setDisableTarget] = useState<{
    member_id: string;
    display_name: string;
  } | null>(null);
  const rotateIntent = useIntentKey();
  const disableIntent = useIntentKey();
  const installState = useSyncExternalStore(
    subscribePwaInstall,
    getPwaInstallSnapshot,
    getPwaInstallSnapshot,
  );
  const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent);
  const settings = useQuery({
    queryKey: ['settings', spaceId],
    queryFn: async () => {
      const result = await rpc<SpaceSettings>('get_space_settings', {
        space_id: spaceId,
      });
      assertRouteSpace(spaceId, result.data.space.id, 'settings_space');
      return result;
    },
  });
  const rotate = useMutation({
    mutationFn: () =>
      rpc<{ invite_url: string; invite_version: number }>('rotate_invite', {
        space_id: spaceId,
        idempotency_key: rotateIntent.get(spaceId),
      }),
    onSuccess: async ({ data }) => {
      rotateIntent.clear();
      const inviteUrl = normalizeInviteUrl(data.invite_url);
      if (!inviteUrl) {
        setCopyError(true);
        return;
      }
      localStorage.setItem(`youjian:invite:${spaceId}`, inviteUrl);
      setConfirmRotate(false);
      try {
        await navigator.clipboard.writeText(inviteUrl);
        setCopied(true);
        setCopyError(false);
        window.setTimeout(() => setCopied(false), 3000);
      } catch {
        setCopied(false);
        setCopyError(true);
      }
    },
  });
  const disable = useMutation({
    mutationFn: (memberId: string) =>
      rpc('disable_member', {
        space_id: spaceId,
        member_id: memberId,
        idempotency_key: disableIntent.get(`${spaceId}:${memberId}`),
      }),
    onSuccess: () => {
      disableIntent.clear();
      setDisableTarget(null);
      void client.invalidateQueries({ queryKey: ['settings', spaceId] });
    },
  });
  const invite = normalizeInviteUrl(
    localStorage.getItem(`youjian:invite:${spaceId}`),
  );
  const copy = async () => {
    if (!invite) {
      rotate.reset();
      setConfirmRotate(true);
      return;
    }
    try {
      await navigator.clipboard.writeText(invite);
      setCopyError(false);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 3000);
    } catch {
      setCopied(false);
      setCopyError(true);
    }
  };
  const data = settings.data?.data;
  const share = async () => {
    if (!invite) {
      rotate.reset();
      setConfirmRotate(true);
      return;
    }
    if (!navigator.share) {
      await copy();
      return;
    }
    try {
      await navigator.share({
        title: data ? `加入「${data.space.name}」` : '加入友间',
        text: '和我一起在友间专注。',
        url: invite,
      });
      setShared(true);
      setCopyError(false);
      window.setTimeout(() => setShared(false), 3000);
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      setShared(false);
      setCopyError(true);
    }
  };
  const exitCurrentDevice = async () => {
    setExiting(true);
    setExitError(false);
    const { error } = await getSupabaseClient().auth.signOut({
      scope: 'local',
    });
    if (error) {
      setExiting(false);
      setExitError(true);
      return;
    }
    for (let index = localStorage.length - 1; index >= 0; index -= 1) {
      const key = localStorage.key(index);
      if (key?.startsWith('youjian:')) localStorage.removeItem(key);
    }
    sessionStorage.clear();
    client.clear();
    window.location.replace('/');
  };
  return (
    <div className="page settings-page">
      <header className="page-header">
        <div>
          <p className="eyebrow">空间与身份</p>
          <h1>设置</h1>
        </div>
      </header>
      {settings.isLoading ? (
        <PageLoader />
      ) : !data ? (
        <ErrorState onRetry={() => void settings.refetch()} />
      ) : (
        <>
          {settings.error && (
            <div className="inline-notice inline-notice--warning" role="status">
              设置暂时没有更新，正在显示上次成功加载的数据。
              <button type="button" onClick={() => void settings.refetch()}>
                重新加载
              </button>
            </div>
          )}
          <section className="settings-card">
            <div className="section-heading">
              <h2>{data.space.name}</h2>
              <span>{data.me.role === 'owner' ? '房主' : '成员'}</span>
            </div>
            <dl className="detail-list">
              <div>
                <dt>你的昵称</dt>
                <dd>{data.me.display_name}</dd>
              </div>
              <div>
                <dt>房间时区</dt>
                <dd>{data.space.timezone}</dd>
              </div>
              <div>
                <dt>每日打卡</dt>
                <dd>{data.space.daily_checkin_target_minutes} 分钟</dd>
              </div>
              <div>
                <dt>成员上限</dt>
                <dd>{data.space.member_limit} 人</dd>
              </div>
              {data.space.created_at && (
                <div>
                  <dt>创建时间</dt>
                  <dd>
                    {formatLocalDateTime(
                      data.space.created_at,
                      data.space.timezone,
                    )}
                  </dd>
                </div>
              )}
            </dl>
          </section>
          {data.owner_actions.can_copy_invite && (
            <section className="settings-card">
              <div className="section-heading">
                <h2>邀请链接</h2>
                <Icon name="copy" />
              </div>
              <p>
                {invite
                  ? '明文邀请链接只保存在当前浏览器中。'
                  : '当前设备没有保存邀请链接，生成新链接会让旧链接立即失效。'}
              </p>
              <button
                className="button button--primary button--full"
                onClick={() => void copy()}
              >
                {copied ? '已复制' : invite ? '复制邀请链接' : '生成新邀请链接'}
              </button>
              {invite && (
                <button
                  className="button button--secondary button--full"
                  onClick={() => void share()}
                >
                  {shared ? '已打开分享' : '分享邀请链接'}
                </button>
              )}
              {copyError && (
                <div
                  className="inline-notice inline-notice--error"
                  role="alert"
                >
                  无法访问剪贴板，请检查浏览器权限后重试。
                </div>
              )}
              {invite && (
                <button
                  className="button button--text button--full"
                  onClick={() => {
                    rotate.reset();
                    setConfirmRotate(true);
                  }}
                >
                  轮换邀请链接
                </button>
              )}
            </section>
          )}
          <section className="settings-card">
            <div className="section-heading">
              <h2>成员</h2>
              <span>
                {data.members.filter((m) => m.status === 'active').length} 人
              </span>
            </div>
            {data.members.length ? (
              <div className="settings-members">
                {data.members.map((member) => (
                  <div key={member.member_id}>
                    <span className={`avatar avatar--${member.status}`}>
                      {member.display_name.slice(0, 1)}
                    </span>
                    <div>
                      <strong>{member.display_name}</strong>
                      <small>
                        {member.role === 'owner'
                          ? '房主'
                          : member.status === 'active'
                            ? '成员'
                            : '已停用'}
                      </small>
                    </div>
                    {data.owner_actions.can_disable_members &&
                      member.role !== 'owner' &&
                      member.status === 'active' && (
                        <button
                          className="button button--text-danger"
                          onClick={() => {
                            disable.reset();
                            setDisableTarget(member);
                          }}
                        >
                          停用
                        </button>
                      )}
                  </div>
                ))}
              </div>
            ) : (
              <EmptyState icon="people" title="没有成员">
                <p>成员列表暂时为空。</p>
              </EmptyState>
            )}
          </section>
          <section className="settings-card">
            <div className="section-heading">
              <h2>安装应用</h2>
              <span>{installState.installed ? '已安装' : '可选'}</span>
            </div>
            {installState.installed ? (
              <p>友间已作为独立应用安装在当前设备。</p>
            ) : installState.promptEvent ? (
              <>
                <p>安装后可以从桌面直接打开，并使用已缓存的应用外壳。</p>
                <button
                  className="button button--primary button--full"
                  onClick={() => {
                    setInstallError(false);
                    void promptPwaInstall().catch(() => setInstallError(true));
                  }}
                >
                  安装友间
                </button>
              </>
            ) : isIos ? (
              <p>在 Safari 中点按“分享”，再选择“添加到主屏幕”。</p>
            ) : (
              <p>
                当前浏览器尚未提供安装入口；可在浏览器菜单中查找“安装应用”。
              </p>
            )}
            {installError && (
              <div className="inline-notice inline-notice--error" role="alert">
                安装提示未能打开，请通过浏览器菜单重试。
              </div>
            )}
            <small>应用版本 {packageInfo.version}</small>
          </section>
          <section className="settings-card">
            <h2>关于身份</h2>
            <p>
              匿名身份只保存在当前设备。清除浏览器数据、更换设备或删除 PWA
              数据后无法恢复。
            </p>
            <div className="legal-links">
              <a href="/identity.html">身份与数据说明</a>
              <a href="/privacy.html">隐私说明</a>
            </div>
            <button
              className="button button--text-danger button--full"
              onClick={() => {
                setExitError(false);
                setConfirmExit(true);
              }}
            >
              退出当前设备
            </button>
          </section>
        </>
      )}
      {confirmRotate && (
        <AccessibleModal
          kind="dialog"
          titleId="rotate-title"
          onClose={() => {
            if (!rotate.isPending) setConfirmRotate(false);
          }}
          closeOnBackdrop={!rotate.isPending}
        >
          <h2 id="rotate-title">生成新的邀请链接？</h2>
          <p>旧链接会立即失效，已经加入的成员不受影响。</p>
          {rotate.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {rotate.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              autoFocus
              className="button button--secondary"
              disabled={rotate.isPending}
              onClick={() => setConfirmRotate(false)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={rotate.isPending}
              onClick={() => rotate.mutate()}
            >
              {rotate.isPending ? '正在生成…' : '确认轮换'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {confirmExit && (
        <AccessibleModal
          kind="dialog"
          titleId="exit-device-title"
          onClose={() => {
            if (!exiting) setConfirmExit(false);
          }}
          closeOnBackdrop={!exiting}
        >
          <h2 id="exit-device-title">退出当前设备？</h2>
          <p>
            这个匿名身份无法再次登录。退出后，本设备上的邀请和身份缓存会被清除；友间中的历史记录仍会保留。
          </p>
          <p>若正在专注，请先结束本次专注再退出。</p>
          {exitError && (
            <div className="inline-notice inline-notice--error" role="alert">
              无法清除当前身份，请检查连接后重试。
            </div>
          )}
          <div className="dialog__actions">
            <button
              autoFocus
              className="button button--secondary"
              disabled={exiting}
              onClick={() => setConfirmExit(false)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={exiting}
              onClick={() => void exitCurrentDevice()}
            >
              {exiting ? '正在退出…' : '确认退出'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {disableTarget && (
        <AccessibleModal
          kind="dialog"
          titleId="disable-title"
          onClose={() => {
            if (!disable.isPending) setDisableTarget(null);
          }}
          closeOnBackdrop={!disable.isPending}
        >
          <h2 id="disable-title">停用 {disableTarget.display_name}？</h2>
          <p>
            对方会立即失去访问权限；正在进行的专注会按服务端时间结算，历史记录仍会保留。
          </p>
          {disable.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {disable.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              autoFocus
              className="button button--secondary"
              disabled={disable.isPending}
              onClick={() => setDisableTarget(null)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={disable.isPending}
              onClick={() => disable.mutate(disableTarget.member_id)}
            >
              {disable.isPending ? '正在停用…' : '确认停用'}
            </button>
          </div>
        </AccessibleModal>
      )}
    </div>
  );
}
