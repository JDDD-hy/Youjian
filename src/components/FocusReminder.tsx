import { useEffect, useState } from 'react';
import type { FocusSession } from '../domain/types';
import { calculateFocusSeconds } from '../hooks/useServerClock';
import {
  FOCUS_REMINDER_DELAY_MS,
  closeFocusReminder,
  enableFocusReminder,
  readFocusReminderEnabled,
  setFocusReminderEnabled,
  showFocusReminder,
  supportsFocusReminder,
} from '../lib/focusReminder';

export function FocusReminder({ session }: { session: FocusSession }) {
  const supported = supportsFocusReminder();
  const [enabled, setEnabled] = useState(readFocusReminderEnabled);
  const [permission, setPermission] = useState<
    NotificationPermission | 'unsupported'
  >(supported ? Notification.permission : 'unsupported');

  useEffect(() => {
    if (session.status !== 'focusing' || !enabled || permission !== 'granted') {
      void closeFocusReminder();
      return;
    }

    let timer: number | undefined;
    const cancel = () => {
      if (timer !== undefined) window.clearTimeout(timer);
      timer = undefined;
    };
    const schedule = () => {
      cancel();
      timer = window.setTimeout(() => {
        void showFocusReminder({
          taskName: session.task_name,
          focusedSeconds: calculateFocusSeconds(session, Date.now()),
          url: window.location.href,
        });
      }, FOCUS_REMINDER_DELAY_MS);
    };
    const isAway = () =>
      document.visibilityState === 'hidden' || !document.hasFocus();
    const handleVisibility = () => {
      if (isAway()) schedule();
      else {
        cancel();
        void closeFocusReminder();
      }
    };

    document.addEventListener('visibilitychange', handleVisibility);
    window.addEventListener('blur', schedule);
    window.addEventListener('focus', handleVisibility);
    if (isAway()) schedule();
    return () => {
      cancel();
      document.removeEventListener('visibilitychange', handleVisibility);
      window.removeEventListener('blur', schedule);
      window.removeEventListener('focus', handleVisibility);
    };
  }, [enabled, permission, session]);

  if (!supported) return null;

  const turnOn = async () => {
    const result = await enableFocusReminder();
    setPermission(result);
    setEnabled(result === 'granted');
  };
  const turnOff = () => {
    setFocusReminderEnabled(false);
    setEnabled(false);
    void closeFocusReminder();
  };

  return (
    <section className="focus-reminder" aria-label="桌面专注提醒">
      <div>
        <strong>桌面提醒</strong>
        <p>
          {permission === 'denied'
            ? '浏览器已阻止通知，请在地址栏的网站设置中重新允许。'
            : enabled
              ? '已开启。页面最小化或切走 2 分钟后提醒你。'
              : '页面最小化后，用 Windows 通知提醒专注仍在进行。'}
        </p>
      </div>
      {permission !== 'denied' && (
        <button
          className="button button--text"
          type="button"
          onClick={() => (enabled ? turnOff() : void turnOn())}
        >
          {enabled ? '关闭' : '开启提醒'}
        </button>
      )}
    </section>
  );
}
