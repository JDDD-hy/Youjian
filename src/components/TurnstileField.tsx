import { useEffect, useId, useRef, useState } from 'react';

declare global {
  interface Window {
    turnstile?: {
      render: (
        target: string,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          'expired-callback': () => void;
          theme: 'light';
          size: 'flexible';
        },
      ) => string;
    };
  }
}

export function TurnstileField({
  onToken,
}: {
  onToken: (token: string | undefined) => void;
}) {
  const siteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY;
  const reactId = useId();
  const id = `turnstile-${reactId.replaceAll(':', '')}`;
  const [failed, setFailed] = useState(false);
  const callbackRef = useRef(onToken);
  useEffect(() => {
    callbackRef.current = onToken;
  }, [onToken]);
  useEffect(() => {
    if (!siteKey) return;
    const render = () =>
      window.turnstile?.render(`#${id}`, {
        sitekey: siteKey,
        callback: (token) => callbackRef.current(token),
        'expired-callback': () => callbackRef.current(undefined),
        theme: 'light',
        size: 'flexible',
      });
    if (window.turnstile) {
      render();
      return;
    }
    const script = document.createElement('script');
    script.src =
      'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.async = true;
    script.defer = true;
    script.onload = render;
    script.onerror = () => setFailed(true);
    document.head.append(script);
  }, [id, siteKey]);
  if (!siteKey) return null;
  return (
    <div className="captcha-field">
      {failed ? (
        <p className="field-error">安全验证加载失败，请刷新后重试。</p>
      ) : (
        <div id={id} />
      )}
    </div>
  );
}
