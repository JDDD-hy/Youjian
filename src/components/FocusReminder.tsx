import { useEffect, useRef, useState } from 'react';
import type { FocusSession } from '../domain/types';
import { calculateFocusSeconds } from '../hooks/useServerClock';
import {
  PAUSED_FOCUS_WARNING_DELAY_MS,
  announceFocusReminderReset,
  closeFocusReminder,
  enableFocusReminder,
  getFocusReminderDelay,
  getFocusReminderResetKey,
  readFocusReminderEnabled,
  releasePausedFocusWarning,
  releaseFocusReminder,
  reservePausedFocusWarning,
  reserveFocusReminder,
  setFocusReminderEnabled,
  showFocusReminder,
  showPausedFocusWarning,
  supportsFocusReminder,
} from '../lib/focusReminder';

export function FocusReminder({ session }: { session: FocusSession }) {
  const sessionRef = useRef(session);
  const supported = supportsFocusReminder();
  const [enabled, setEnabled] = useState(readFocusReminderEnabled);
  const [permission, setPermission] = useState<
    NotificationPermission | 'unsupported'
  >(supported ? Notification.permission : 'unsupported');

  useEffect(() => {
    sessionRef.current = session;
  }, [session]);

  useEffect(() => {
    if (
      (session.status !== 'focusing' && session.status !== 'paused') ||
      !enabled ||
      permission !== 'granted'
    ) {
      releaseFocusReminder(session.session_id);
      releasePausedFocusWarning(session.session_id);
      announceFocusReminderReset(session.session_id);
      void closeFocusReminder();
      return;
    }

    const sessionId = session.session_id;
    const isAway = () =>
      document.visibilityState === 'hidden' || !document.hasFocus();

    if (session.status === 'paused') {
      releaseFocusReminder(sessionId);
      void closeFocusReminder();

      const pausedAt = Date.parse(session.paused_at ?? '');
      const autoSettleAt = Date.parse(session.auto_settle_at ?? '');
      if (!Number.isFinite(pausedAt) || !Number.isFinite(autoSettleAt)) {
        releasePausedFocusWarning(sessionId);
        return;
      }

      let timer: number | undefined;
      const cancel = () => {
        if (timer !== undefined) window.clearTimeout(timer);
        timer = undefined;
      };
      const schedule = () => {
        if (!isAway() || timer !== undefined || Date.now() >= autoSettleAt)
          return;
        const warningAt = pausedAt + PAUSED_FOCUS_WARNING_DELAY_MS;
        timer = window.setTimeout(
          () => {
            timer = undefined;
            const currentSession = sessionRef.current;
            const currentAutoSettleAt = Date.parse(
              currentSession.auto_settle_at ?? '',
            );
            if (
              !isAway() ||
              currentSession.session_id !== sessionId ||
              currentSession.status !== 'paused' ||
              !Number.isFinite(currentAutoSettleAt) ||
              Date.now() >= currentAutoSettleAt
            )
              return;

            const token = reservePausedFocusWarning(sessionId);
            if (!token) return;
            void showPausedFocusWarning({
              taskName: currentSession.task_name,
              remainingSeconds: Math.max(
                0,
                (currentAutoSettleAt - Date.now()) / 1000,
              ),
              url: window.location.href,
            }).then((shown) => {
              if (!shown) releasePausedFocusWarning(sessionId, token);
              else if (!isAway()) void closeFocusReminder();
            });
          },
          Math.max(0, warningAt - Date.now()),
        );
      };
      const handleVisibility = () => {
        if (isAway()) schedule();
        else {
          cancel();
          announceFocusReminderReset(sessionId);
          void closeFocusReminder();
        }
      };
      const handleStorage = (event: StorageEvent) => {
        if (event.key !== getFocusReminderResetKey(sessionId)) return;
        cancel();
        void closeFocusReminder();
      };

      document.addEventListener('visibilitychange', handleVisibility);
      window.addEventListener('blur', schedule);
      window.addEventListener('focus', handleVisibility);
      window.addEventListener('storage', handleStorage);
      handleVisibility();
      return () => {
        cancel();
        releasePausedFocusWarning(sessionId);
        announceFocusReminderReset(sessionId);
        document.removeEventListener('visibilitychange', handleVisibility);
        window.removeEventListener('blur', schedule);
        window.removeEventListener('focus', handleVisibility);
        window.removeEventListener('storage', handleStorage);
      };
    }

    releasePausedFocusWarning(sessionId);
    let timer: number | undefined;
    let awayStartedAt: number | undefined;
    let nextReminderIndex = 0;
    const cancel = () => {
      if (timer !== undefined) window.clearTimeout(timer);
      timer = undefined;
    };
    const schedule = () => {
      if (!isAway() || timer !== undefined) return;
      awayStartedAt ??= Date.now();
      const remaining = Math.max(
        0,
        awayStartedAt + getFocusReminderDelay(nextReminderIndex) - Date.now(),
      );
      timer = window.setTimeout(() => {
        timer = undefined;
        if (!isAway() || awayStartedAt === undefined) return;

        const elapsed = Date.now() - awayStartedAt;
        let reminderIndex = nextReminderIndex;
        while (getFocusReminderDelay(reminderIndex + 1) <= elapsed) {
          reminderIndex += 1;
        }
        nextReminderIndex = reminderIndex + 1;

        const token = reserveFocusReminder(sessionId, reminderIndex);
        schedule();
        if (!token) return;

        const currentSession = sessionRef.current;
        void showFocusReminder({
          taskName: currentSession.task_name,
          focusedSeconds: calculateFocusSeconds(currentSession, Date.now()),
          awaySeconds: elapsed / 1000,
          url: window.location.href,
        }).then((shown) => {
          if (!shown) {
            releaseFocusReminder(sessionId, token);
          } else if (!isAway()) {
            void closeFocusReminder();
          }
        });
      }, remaining);
    };
    const resetAway = (announce = true) => {
      cancel();
      awayStartedAt = undefined;
      nextReminderIndex = 0;
      releaseFocusReminder(sessionId);
      if (announce) announceFocusReminderReset(sessionId);
    };
    const handleVisibility = () => {
      if (isAway()) schedule();
      else {
        resetAway();
        void closeFocusReminder();
      }
    };
    const handleStorage = (event: StorageEvent) => {
      if (event.key !== getFocusReminderResetKey(sessionId)) return;
      resetAway(false);
      void closeFocusReminder();
    };

    document.addEventListener('visibilitychange', handleVisibility);
    window.addEventListener('blur', schedule);
    window.addEventListener('focus', handleVisibility);
    window.addEventListener('storage', handleStorage);
    handleVisibility();
    return () => {
      resetAway();
      document.removeEventListener('visibilitychange', handleVisibility);
      window.removeEventListener('blur', schedule);
      window.removeEventListener('focus', handleVisibility);
      window.removeEventListener('storage', handleStorage);
    };
  }, [
    enabled,
    permission,
    session.auto_settle_at,
    session.paused_at,
    session.session_id,
    session.status,
  ]);

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
              ? '已开启。离开 2 分钟后提醒，持续离开则在 30 分钟后每小时提醒；暂停 10 分钟时预警自动结束。'
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
