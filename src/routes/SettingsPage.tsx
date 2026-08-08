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
import { loadInviteUrl, saveInviteUrl } from '../lib/inviteUrl';
import { appPath, appBasePath } from '../lib/appBase';
import { clearDeviceIdentity } from '../lib/deviceIdentity';
import {
  downloadRecoveryCodes,
  rotateRecoveryCodes,
  type RecoveryCodeSet,
} from '../lib/recoveryCodes';

export function SettingsPage() {
  const { spaceId = '' } = useParams();
  const client = useQueryClient();
  const [copied, setCopied] = useState(false);
  const [shared, setShared] = useState(false);
  const [copyError, setCopyError] = useState(false);
  const [installError, setInstallError] = useState(false);
  const [confirmRotate, setConfirmRotate] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [spaceName, setSpaceName] = useState('');
  const [memberLimitTarget, setMemberLimitTarget] = useState<number | null>(
    null,
  );
  const [confirmExit, setConfirmExit] = useState(false);
  const [exiting, setExiting] = useState(false);
  const [exitError, setExitError] = useState(false);
  const [disableTarget, setDisableTarget] = useState<{
    member_id: string;
    display_name: string;
  } | null>(null);
  const [transferTarget, setTransferTarget] = useState<{
    member_id: string;
    display_name: string;
  } | null>(null);
  const [confirmLeave, setConfirmLeave] = useState(false);
  const [confirmDissolve, setConfirmDissolve] = useState(false);
  const [transferCode, setTransferCode] = useState<{
    value: string;
    expiresAt: string;
  } | null>(null);
  const [transferCodeCopied, setTransferCodeCopied] = useState(false);
  const [memberRecoveryCode, setMemberRecoveryCode] = useState<{
    value: string;
    expiresAt: string;
    memberName: string;
  } | null>(null);
  const [memberRecoveryCodeCopied, setMemberRecoveryCodeCopied] =
    useState(false);
  const [recoveryCodeSet, setRecoveryCodeSet] =
    useState<RecoveryCodeSet | null>(null);
  const rotateIntent = useIntentKey();
  const disableIntent = useIntentKey();
  const lifecycleIntent = useIntentKey();
  const settingsIntent = useIntentKey();
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
      const inviteUrl = saveInviteUrl(spaceId, data.invite_url);
      if (!inviteUrl) {
        setCopyError(true);
        return;
      }
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
  const renameSpace = useMutation({
    mutationFn: (name: string) =>
      rpc('update_space_name', {
        space_id: spaceId,
        name,
        idempotency_key: settingsIntent.get(`name:${spaceId}:${name.trim()}`),
      }),
    onSuccess: () => {
      settingsIntent.clear();
      setEditingName(false);
      void client.invalidateQueries({ queryKey: ['settings', spaceId] });
      void client.invalidateQueries({ queryKey: ['home', spaceId] });
      void client.invalidateQueries({ queryKey: ['invite'] });
    },
  });
  const increaseLimit = useMutation({
    mutationFn: (memberLimit: number) =>
      rpc('increase_member_limit', {
        space_id: spaceId,
        member_limit: memberLimit,
        idempotency_key: settingsIntent.get(`limit:${spaceId}:${memberLimit}`),
      }),
    onSuccess: () => {
      settingsIntent.clear();
      setMemberLimitTarget(null);
      void client.invalidateQueries({ queryKey: ['settings', spaceId] });
      void client.invalidateQueries({ queryKey: ['home', spaceId] });
      void client.invalidateQueries({ queryKey: ['invite'] });
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
  const leave = useMutation({
    mutationFn: () =>
      rpc('leave_space', {
        space_id: spaceId,
        idempotency_key: lifecycleIntent.get(`leave:${spaceId}`),
      }),
    onSuccess: () => {
      lifecycleIntent.clear();
      localStorage.removeItem(`youjian:invite:${spaceId}`);
      client.clear();
      window.location.assign(appBasePath);
    },
  });
  const transfer = useMutation({
    mutationFn: (memberId: string) =>
      rpc('transfer_ownership', {
        space_id: spaceId,
        target_member_id: memberId,
        idempotency_key: lifecycleIntent.get(`transfer:${spaceId}:${memberId}`),
      }),
    onSuccess: () => {
      lifecycleIntent.clear();
      setTransferTarget(null);
      void client.invalidateQueries({ queryKey: ['settings', spaceId] });
      void client.invalidateQueries({ queryKey: ['home', spaceId] });
    },
  });
  const dissolve = useMutation({
    mutationFn: () =>
      rpc('dissolve_space', {
        space_id: spaceId,
        idempotency_key: lifecycleIntent.get(`dissolve:${spaceId}`),
      }),
    onSuccess: () => {
      lifecycleIntent.clear();
      localStorage.removeItem(`youjian:invite:${spaceId}`);
      client.clear();
      window.location.assign(appBasePath);
    },
  });
  const createTransferCode = useMutation({
    mutationFn: () =>
      rpc<{ transfer_code: string; expires_at: string }>(
        'create_identity_transfer_code',
      ),
    onSuccess: ({ data }) => {
      setTransferCode({
        value: data.transfer_code,
        expiresAt: data.expires_at,
      });
      setTransferCodeCopied(false);
    },
  });
  const createMemberRecoveryCode = useMutation({
    mutationFn: (member: { member_id: string; display_name: string }) =>
      rpc<{
        transfer_code: string;
        expires_at: string;
        member: { member_id: string; display_name: string };
      }>('create_member_recovery_code', {
        space_id: spaceId,
        member_id: member.member_id,
      }),
    onSuccess: ({ data }) => {
      setMemberRecoveryCode({
        value: data.transfer_code,
        expiresAt: data.expires_at,
        memberName: data.member.display_name,
      });
      setMemberRecoveryCodeCopied(false);
    },
  });
  const createRecoveryCodes = useMutation({
    mutationFn: rotateRecoveryCodes,
    onSuccess: ({ data }) => setRecoveryCodeSet(data),
  });
  const invite = loadInviteUrl(spaceId);
  const copy = async () => {
    if (!invite) {
      rotate.reset();
      setConfirmRotate(true);
      return;
    }
    try {
      await navigator.clipboard.writeText(loadInviteUrl(spaceId) ?? invite);
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
        url: loadInviteUrl(spaceId) ?? invite,
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
    await clearDeviceIdentity(client);
    window.location.replace(appBasePath);
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
              {data.owner_actions.can_update_space_name ? (
                <button
                  className="button button--text button--compact"
                  onClick={() => {
                    renameSpace.reset();
                    setSpaceName(data.space.name);
                    setEditingName(true);
                  }}
                >
                  修改名称
                </button>
              ) : (
                <span>成员</span>
              )}
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
                <dt>成员上限</dt>
                <dd>
                  {data.space.member_limit} 人{' '}
                  {data.owner_actions.can_increase_member_limit && (
                    <button
                      className="button button--text button--compact"
                      onClick={() => {
                        increaseLimit.reset();
                        setMemberLimitTarget(data.space.member_limit + 1);
                      }}
                    >
                      提高上限
                    </button>
                  )}
                </dd>
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
                    {data.me.role === 'owner' &&
                      member.role !== 'owner' &&
                      member.status === 'active' && (
                        <button
                          className="button button--text"
                          disabled={createMemberRecoveryCode.isPending}
                          onClick={() =>
                            createMemberRecoveryCode.mutate(member)
                          }
                        >
                          协助恢复
                        </button>
                      )}
                    {data.me.role === 'owner' &&
                      member.role !== 'owner' &&
                      member.status === 'active' && (
                        <button
                          className="button button--text"
                          onClick={() => {
                            transfer.reset();
                            setTransferTarget(member);
                          }}
                        >
                          转让房主
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
              <a href={appPath('identity.html')}>身份与数据说明</a>
              <a href={appPath('privacy.html')}>隐私说明</a>
            </div>
            <button
              className="button button--secondary button--full"
              disabled={createTransferCode.isPending}
              onClick={() => createTransferCode.mutate()}
            >
              {createTransferCode.isPending ? '正在生成…' : '生成身份迁移码'}
            </button>
            <button
              className="button button--secondary button--full"
              disabled={createRecoveryCodes.isPending}
              onClick={() => createRecoveryCodes.mutate()}
            >
              {createRecoveryCodes.isPending
                ? '正在生成…'
                : '生成长期身份恢复码'}
            </button>
            {createRecoveryCodes.error && (
              <div className="inline-notice inline-notice--error" role="alert">
                {createRecoveryCodes.error.message}
              </div>
            )}
            {createTransferCode.error && (
              <div className="inline-notice inline-notice--error" role="alert">
                {createTransferCode.error.message}
              </div>
            )}
            <button
              className="button button--text-danger button--full"
              onClick={() => {
                leave.reset();
                setConfirmLeave(true);
              }}
            >
              主动退出友间
            </button>
            {data.me.role === 'owner' && (
              <button
                className="button button--text-danger button--full"
                onClick={() => {
                  dissolve.reset();
                  setConfirmDissolve(true);
                }}
              >
                解散友间
              </button>
            )}
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
      {editingName && data && (
        <AccessibleModal
          kind="dialog"
          titleId="rename-space-title"
          onClose={() => {
            if (!renameSpace.isPending) setEditingName(false);
          }}
          closeOnBackdrop={!renameSpace.isPending}
        >
          <h2 id="rename-space-title">修改友间名称</h2>
          <label className="field">
            <span>新名称</span>
            <input
              autoFocus
              maxLength={30}
              value={spaceName}
              onChange={(event) => setSpaceName(event.target.value)}
            />
          </label>
          {renameSpace.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {renameSpace.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              className="button button--secondary"
              disabled={renameSpace.isPending}
              onClick={() => setEditingName(false)}
            >
              取消
            </button>
            <button
              className="button button--primary"
              disabled={
                renameSpace.isPending ||
                !spaceName.trim() ||
                spaceName.trim() === data.space.name
              }
              onClick={() => renameSpace.mutate(spaceName)}
            >
              {renameSpace.isPending ? '正在保存…' : '保存名称'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {memberLimitTarget !== null && data && (
        <AccessibleModal
          kind="dialog"
          titleId="member-limit-title"
          onClose={() => {
            if (!increaseLimit.isPending) setMemberLimitTarget(null);
          }}
          closeOnBackdrop={!increaseLimit.isPending}
        >
          <h2 id="member-limit-title">提高成员上限</h2>
          <label className="field">
            <span>新上限</span>
            <select
              autoFocus
              value={memberLimitTarget}
              onChange={(event) =>
                setMemberLimitTarget(Number(event.target.value))
              }
            >
              {Array.from(
                { length: 12 - data.space.member_limit },
                (_, index) => data.space.member_limit + index + 1,
              ).map((limit) => (
                <option value={limit} key={limit}>
                  {limit} 人
                </option>
              ))}
            </select>
          </label>
          <p>
            将从 {data.space.member_limit} 人提高到 {memberLimitTarget}{' '}
            人。保存后不能调低，现有邀请链接继续有效。
          </p>
          {increaseLimit.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {increaseLimit.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              className="button button--secondary"
              disabled={increaseLimit.isPending}
              onClick={() => setMemberLimitTarget(null)}
            >
              取消
            </button>
            <button
              className="button button--primary"
              disabled={increaseLimit.isPending}
              onClick={() => increaseLimit.mutate(memberLimitTarget)}
            >
              {increaseLimit.isPending ? '正在保存…' : '确认提高'}
            </button>
          </div>
        </AccessibleModal>
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
      {transferCode && (
        <AccessibleModal
          kind="dialog"
          titleId="identity-transfer-title"
          onClose={() => setTransferCode(null)}
        >
          <h2 id="identity-transfer-title">身份迁移码</h2>
          <p>
            请在 10
            分钟内到新设备的“迁移已有身份”页面输入。成功后，本设备会立即失去访问权。
          </p>
          <output aria-label="一次性身份迁移码" className="transfer-code">
            {transferCode.value}
          </output>
          <small>
            有效期至{' '}
            {formatLocalDateTime(
              transferCode.expiresAt,
              data?.space.timezone ?? 'UTC',
            )}
          </small>
          <div className="dialog__actions">
            <button
              className="button button--secondary"
              onClick={() => setTransferCode(null)}
            >
              关闭
            </button>
            <button
              autoFocus
              className="button button--primary"
              onClick={() => {
                void navigator.clipboard
                  .writeText(transferCode.value)
                  .then(() => setTransferCodeCopied(true));
              }}
            >
              {transferCodeCopied ? '已复制' : '复制迁移码'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {memberRecoveryCode && (
        <AccessibleModal
          kind="dialog"
          titleId="member-recovery-title"
          onClose={() => setMemberRecoveryCode(null)}
        >
          <h2 id="member-recovery-title">
            恢复 {memberRecoveryCode.memberName} 的身份
          </h2>
          <p>
            将此一次性恢复码私下发送给该成员。对方在欢迎页进入“恢复已有身份”并输入；成功后会恢复原成员、历史记录和加入顺序，旧登录凭证立即失效。
          </p>
          <output aria-label="成员身份恢复码" className="transfer-code">
            {memberRecoveryCode.value}
          </output>
          <small>
            有效期至{' '}
            {formatLocalDateTime(
              memberRecoveryCode.expiresAt,
              data?.space.timezone ?? 'UTC',
            )}
          </small>
          <div className="dialog__actions">
            <button
              className="button button--secondary"
              onClick={() => setMemberRecoveryCode(null)}
            >
              关闭
            </button>
            <button
              autoFocus
              className="button button--primary"
              onClick={() => {
                void navigator.clipboard
                  .writeText(memberRecoveryCode.value)
                  .then(() => setMemberRecoveryCodeCopied(true));
              }}
            >
              {memberRecoveryCodeCopied ? '已复制' : '复制恢复码'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {recoveryCodeSet && data && (
        <AccessibleModal
          kind="dialog"
          titleId="recovery-codes-title"
          onClose={() => setRecoveryCodeSet(null)}
        >
          <h2 id="recovery-codes-title">长期身份恢复码</h2>
          <p>
            这是恢复当前身份的唯一长期凭证。每个码只能使用一次；重新生成后旧码全部失效。请下载并保存到密码管理器、个人云盘或离线介质。
          </p>
          <ol className="recovery-code-list">
            {recoveryCodeSet.codes.map((code) => (
              <li key={code}>
                <code>{code}</code>
              </li>
            ))}
          </ol>
          <div className="dialog__actions">
            <button
              className="button button--secondary"
              onClick={() => setRecoveryCodeSet(null)}
            >
              关闭
            </button>
            <button
              autoFocus
              className="button button--primary"
              onClick={() =>
                downloadRecoveryCodes(
                  recoveryCodeSet.codes,
                  data.me.display_name,
                  recoveryCodeSet.generated_at,
                )
              }
            >
              下载 .txt
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
      {confirmLeave && (
        <AccessibleModal
          kind="dialog"
          titleId="leave-space-title"
          onClose={() => {
            if (!leave.isPending) setConfirmLeave(false);
          }}
          closeOnBackdrop={!leave.isPending}
        >
          <h2 id="leave-space-title">主动退出友间？</h2>
          <p>
            退出后会立即失去访问权并保留历史记录；之后可凭当前有效邀请重新加入。
          </p>
          {data?.me.role === 'owner' && (
            <p>房主需要先转让房主，或改为解散友间。</p>
          )}
          {leave.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {leave.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              autoFocus
              className="button button--secondary"
              disabled={leave.isPending}
              onClick={() => setConfirmLeave(false)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={leave.isPending || data?.me.role === 'owner'}
              onClick={() => leave.mutate()}
            >
              {leave.isPending ? '正在退出…' : '确认退出友间'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {transferTarget && (
        <AccessibleModal
          kind="dialog"
          titleId="transfer-owner-title"
          onClose={() => {
            if (!transfer.isPending) setTransferTarget(null);
          }}
          closeOnBackdrop={!transfer.isPending}
        >
          <h2 id="transfer-owner-title">
            转让房主给 {transferTarget.display_name}？
          </h2>
          <p>转让后对方成为房主，你将成为普通成员。此操作不能自动撤销。</p>
          {transfer.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {transfer.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              autoFocus
              className="button button--secondary"
              disabled={transfer.isPending}
              onClick={() => setTransferTarget(null)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={transfer.isPending}
              onClick={() => transfer.mutate(transferTarget.member_id)}
            >
              {transfer.isPending ? '正在转让…' : '确认转让'}
            </button>
          </div>
        </AccessibleModal>
      )}
      {confirmDissolve && (
        <AccessibleModal
          kind="dialog"
          titleId="dissolve-space-title"
          onClose={() => {
            if (!dissolve.isPending) setConfirmDissolve(false);
          }}
          closeOnBackdrop={!dissolve.isPending}
        >
          <h2 id="dissolve-space-title">永久解散友间？</h2>
          <p>
            所有成员会立即失去访问权，活动专注先由服务端结算，历史记录仅保留用于审计。
          </p>
          {dissolve.error && (
            <div className="inline-notice inline-notice--error" role="alert">
              {dissolve.error.message}
            </div>
          )}
          <div className="dialog__actions">
            <button
              autoFocus
              className="button button--secondary"
              disabled={dissolve.isPending}
              onClick={() => setConfirmDissolve(false)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={dissolve.isPending}
              onClick={() => dissolve.mutate()}
            >
              {dissolve.isPending ? '正在解散…' : '确认永久解散'}
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
