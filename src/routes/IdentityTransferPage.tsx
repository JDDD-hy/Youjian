import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { TurnstileField } from '../components/TurnstileField';
import { Icon } from '../components/Icons';
import { normalizeRecoveryCredentialInput } from '../lib/recoveryCodes';
import { ensureAnonymousSession, rpc } from '../lib/api';
import { loadMembership } from '../lib/membership';
import { useOnlineStatus } from '../hooks/useOnlineStatus';

export function IdentityTransferPage() {
  const navigate = useNavigate();
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
            const transferCode = normalizeRecoveryCredentialInput(code);
            const isTransferCode = /^[A-Za-z0-9_-]{32}$/.test(transferCode);
            const isRecoveryCode = /^[A-Za-z0-9_-]{22}$/.test(transferCode);
            if (!isTransferCode && !isRecoveryCode) {
              setError('请输入完整的一次性身份码或恢复码。');
              return;
            }
            setPending(true);
            setError('');
            void ensureAnonymousSession(captchaToken)
              .then(() =>
                isRecoveryCode
                  ? rpc('redeem_identity_recovery_code', {
                      recovery_code: transferCode,
                    })
                  : rpc('redeem_identity_transfer_code', {
                      transfer_code: transferCode,
                    }),
              )
              .then(loadMembership)
              .then((state) => {
                const membership = state?.membership;
                void navigate(
                  membership ? `/space/${membership.space_id}` : '/',
                  { replace: true },
                );
              })
              .catch((reason: unknown) => {
                setError(
                  reason instanceof Error
                    ? reason.message
                    : '暂时无法迁移身份，请稍后重试。',
                );
              })
              .finally(() => setPending(false));
          }}
          noValidate
        >
          <label className="field">
            <span>身份码或恢复码</span>
            <input
              autoFocus
              autoComplete="off"
              autoCapitalize="none"
              autoCorrect="off"
              inputMode="text"
              maxLength={64}
              spellCheck={false}
              value={code}
              onChange={(event) => setCode(event.target.value)}
              aria-invalid={Boolean(error)}
              placeholder="22 位恢复码或 32 位一次性身份码"
            />
          </label>
          <TurnstileField onToken={setCaptchaToken} />
          {error && <p className="field-error">{error}</p>}
          <button
            className="button button--primary button--full"
            disabled={pending || !online || (captchaRequired && !captchaToken)}
          >
            {pending ? '正在恢复…' : '恢复到这台设备'}
          </button>
        </form>
      </section>
    </main>
  );
}
