import { Presence } from '../components/Presence';
import { useQueryClient } from '@tanstack/react-query';
import { useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { TurnstileField } from '../components/TurnstileField';
import { Icon } from '../components/Icons';
import { ensureAnonymousSession, rpc } from '../lib/api';
import { loadMembership } from '../lib/membership';
import { useOnlineStatus } from '../hooks/useOnlineStatus';

export function IdentityTransferPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const submitting = useRef(false);
  const [recovered, setRecovered] = useState(false);
  const online = useOnlineStatus();
  const captchaRequired = Boolean(import.meta.env.VITE_TURNSTILE_SITE_KEY);
  const [captchaToken, setCaptchaToken] = useState<string>();
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [pending, setPending] = useState(false);

  return (
    <main className="form-page">
      <section className="form-card" aria-labelledby="transfer-title">
        <Link className="back-link" to="/">
          <Icon name="arrow-left" />
          返回
        </Link>
        <p className="eyebrow">一次性恢复</p>
        <h1 id="transfer-title">恢复已有身份</h1>
        <p className="lead">
          可在原设备的设置页生成身份码；原设备无法登录时，也可请房主在成员列表为你生成恢复码。兑换成功后，本设备接管原身份，旧登录凭证立即失效。
        </p>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            if (submitting.current) return;
            const transferCode = code.trim();
            const isTransferCode = /^[A-Za-z0-9_-]{32}$/.test(transferCode);
            const isRecoveryCode = /^[A-Za-z0-9_-]{22}$/.test(transferCode);
            if (!recovered && !isTransferCode && !isRecoveryCode) {
              setError('请输入完整的一次性身份码或恢复码。');
              return;
            }
            setPending(true);
            submitting.current = true;
            setError('');
            void (async () => {
              if (!recovered) {
                try {
                  await ensureAnonymousSession(captchaToken);
                  await rpc(
                    isRecoveryCode
                      ? 'redeem_identity_recovery_code'
                      : 'redeem_identity_transfer_code',
                    isRecoveryCode
                      ? { recovery_code: transferCode }
                      : { transfer_code: transferCode },
                  );
                } catch (reason) {
                  setError(
                    reason instanceof Error
                      ? reason.message
                      : '暂时无法迁移身份，请稍后重试。',
                  );
                  return;
                }
                setRecovered(true);
                await queryClient.cancelQueries();
                queryClient.clear();
              }
              try {
                const state = await loadMembership();
                if (!state) throw new Error('身份状态暂未同步');
                queryClient.setQueryData(['membership'], state);
                const membership = state.membership;
                void navigate(
                  membership ? `/space/${membership.space_id}` : '/',
                  { replace: true },
                );
              } catch {
                setError('暂时无法进入友间，请重试进入，无需再次兑换恢复码。');
              }
            })().finally(() => {
              submitting.current = false;
              setPending(false);
            });
          }}
          noValidate
        >
          <label className="field">
            <span>身份码或恢复码</span>
            <input
              autoFocus
              disabled={recovered}
              autoComplete="off"
              inputMode="text"
              maxLength={32}
              value={code}
              onChange={(event) => setCode(event.target.value.trim())}
              aria-invalid={!recovered && Boolean(error)}
              placeholder="32 位一次性身份码"
            />
          </label>
          {!recovered && <TurnstileField onToken={setCaptchaToken} />}
          {recovered && <p role="status">身份恢复成功，正在进入友间。</p>}
          <Presence>
            {error && (
              <p className={recovered ? 'lead' : 'field-error'}>{error}</p>
            )}
          </Presence>
          <button
            className="button button--primary button--full"
            disabled={
              pending ||
              !online ||
              (!recovered && captchaRequired && !captchaToken)
            }
          >
            {recovered
              ? pending
                ? '正在进入…'
                : '进入友间'
              : pending
                ? '正在恢复…'
                : '恢复到这台设备'}
          </button>
        </form>
      </section>
    </main>
  );
}
