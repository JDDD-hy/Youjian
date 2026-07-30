import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { TurnstileField } from '../components/TurnstileField';
import { Icon } from '../components/Icons';
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
        <p className="eyebrow">一次性迁移</p>
        <h1 id="transfer-title">迁移已有身份</h1>
        <p className="lead">
          在原设备的设置页生成迁移码。兑换成功后，本设备接管原身份，原设备立即失效。
        </p>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            const transferCode = code.trim();
            if (!/^[A-Za-z0-9_-]{32}$/.test(transferCode)) {
              setError('请输入完整的 32 位迁移码。');
              return;
            }
            setPending(true);
            setError('');
            void ensureAnonymousSession(captchaToken)
              .then(() =>
                rpc('redeem_identity_transfer_code', {
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
            <span>迁移码</span>
            <input
              autoFocus
              autoComplete="off"
              inputMode="text"
              maxLength={32}
              value={code}
              onChange={(event) => setCode(event.target.value.trim())}
              aria-invalid={Boolean(error)}
              placeholder="32 位一次性迁移码"
            />
          </label>
          <TurnstileField onToken={setCaptchaToken} />
          {error && <p className="field-error">{error}</p>}
          <button
            className="button button--primary button--full"
            disabled={pending || !online || (captchaRequired && !captchaToken)}
          >
            {pending ? '正在迁移…' : '迁移到这台设备'}
          </button>
        </form>
      </section>
    </main>
  );
}
