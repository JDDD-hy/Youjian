import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { inviteInputToUrl } from '../lib/inviteUrl';
import { Icon } from '../components/Icons';

export const pendingDisplayNameKey = 'youjian:pending-display-name';

export function JoinWaitingPage() {
  const navigate = useNavigate();
  const [displayName, setDisplayName] = useState(
    () => localStorage.getItem(pendingDisplayNameKey) ?? '',
  );
  const [inviteInput, setInviteInput] = useState('');
  const [fieldError, setFieldError] = useState('');
  const [saved, setSaved] = useState(false);

  return (
    <main className="form-page">
      <section className="form-card" aria-labelledby="waiting-title">
        <Link className="back-link" to="/">
          <Icon name="arrow-left" />
          返回
        </Link>
        <p className="eyebrow">先准备好昵称</p>
        <h1 id="waiting-title">等待加入友间</h1>
        <p className="lead">
          不会创建房间，也不会成为房主。收到邀请后粘贴链接即可加入。
        </p>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            const name = displayName.trim();
            if (!name || name.length > 20) {
              setFieldError('昵称需要包含 1–20 个字符。');
              return;
            }
            localStorage.setItem(pendingDisplayNameKey, name);
            setFieldError('');
            if (!inviteInput.trim()) {
              setSaved(true);
              return;
            }
            const inviteUrl = inviteInputToUrl(inviteInput);
            if (!inviteUrl) {
              setFieldError('请输入有效的邀请链接或邀请码。');
              return;
            }
            void navigate(new URL(inviteUrl).pathname);
          }}
          noValidate
        >
          <label className="field">
            <span>你的昵称</span>
            <input
              autoFocus
              autoComplete="nickname"
              maxLength={20}
              value={displayName}
              onChange={(event) => {
                setDisplayName(event.target.value);
                setSaved(false);
              }}
              aria-invalid={Boolean(fieldError)}
            />
          </label>
          <label className="field">
            <span>邀请链接或邀请码（可稍后填写）</span>
            <input
              inputMode="url"
              autoComplete="off"
              value={inviteInput}
              onChange={(event) => {
                setInviteInput(event.target.value);
                setSaved(false);
              }}
              aria-invalid={Boolean(fieldError)}
            />
          </label>
          {fieldError && <p className="field-error">{fieldError}</p>}
          {saved && (
            <div className="inline-notice" role="status">
              昵称已保存在这台设备。收到邀请后回到这里粘贴即可。
            </div>
          )}
          <button className="button button--primary button--full">
            {inviteInput.trim() ? '打开邀请' : '保存并等待'}
          </button>
        </form>
      </section>
    </main>
  );
}
