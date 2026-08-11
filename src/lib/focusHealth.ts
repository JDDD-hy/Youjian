import type { FocusSession } from '../domain/types';
import { appPath } from './appBase';
import { closeFocusReminder, FOCUS_REMINDER_TAG } from './focusReminder';
import { formatDuration } from './format';

const fallbackTag = FOCUS_REMINDER_TAG;

function notificationAvailable() {
  return (
    typeof Notification !== 'undefined' && Notification.permission === 'granted'
  );
}

export async function showFocusHealthNotification(session: FocusSession) {
  if (!notificationAvailable()) return false;
  await closeFocusReminder();
  const options: NotificationOptions & {
    actions: Array<{ action: string; title: string }>;
  } = {
    body: `你已为「${session.task_name}」亮灯两小时。\n先让目光离开屏幕，也让思绪有片刻留白。\n1 分钟内未选择，本次专注将自动结束。`,
    icon: appPath('lamp-dimmed.svg'),
    badge: appPath('favicon.png'),
    tag: fallbackTag,
    requireInteraction: true,
    data: {
      kind: 'focus-health-check',
      sessionId: session.session_id,
      url: window.location.href,
    },
    actions: [
      { action: 'end', title: '收起此刻' },
      { action: 'continue', title: '继续专注' },
    ],
  };
  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    if (!registration) return false;
    await registration.showNotification('友间 · 灯光走过了两个小时', options);
    return true;
  } catch {
    return false;
  }
}

export async function showFocusHealthResultNotification(
  session: FocusSession,
  continued = false,
) {
  if (!notificationAvailable()) return;
  const registration = await navigator.serviceWorker?.getRegistration();
  if (!registration) return;
  const automatic = session.completion_reason === 'health_check_timeout';
  const title = continued
    ? '友间 · 灯仍亮着'
    : automatic
      ? '友间 · 灯已自动收起'
      : '友间 · 灯已收起';
  const body = continued
    ? '已继续本次专注，之后不再进行休息询问，最长可继续至六小时。'
    : `${automatic ? '两个小时已经走过，本次专注已自动结束。\n' : ''}本次共专注 ${formatDuration(session.credited_focus_seconds ?? 0)}。`;
  await registration.showNotification(title, {
    body,
    icon: appPath(
      continued ? 'lamp-focusing-fixed.svg' : 'lamp-paused-fixed.svg',
    ),
    badge: appPath('favicon.png'),
    tag: fallbackTag,
    data: { kind: 'focus-health-result', url: window.location.href },
  });
  window.setTimeout(() => {
    void registration
      .getNotifications({ tag: fallbackTag })
      .then((items) => items.forEach((item) => item.close()));
  }, 5000);
}

export async function closeFocusHealthNotification() {
  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    const notifications = await registration?.getNotifications({
      tag: fallbackTag,
    });
    notifications?.forEach((notification) => notification.close());
  } catch {
    // Notification cleanup is best effort.
  }
}
