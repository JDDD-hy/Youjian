import { appPath } from './appBase';

export const FOCUS_REMINDER_DELAY_MS = 2 * 60 * 1000;
export const FOCUS_REMINDER_TAG = 'youjian-active-focus';

const enabledKey = 'youjian:focus-reminder-enabled';
let fallbackNotification: Notification | undefined;

export function supportsFocusReminder() {
  return typeof window !== 'undefined' && 'Notification' in window;
}

export function readFocusReminderEnabled() {
  if (!supportsFocusReminder()) return false;
  return localStorage.getItem(enabledKey) === 'true';
}

export function setFocusReminderEnabled(enabled: boolean) {
  if (!supportsFocusReminder()) return;
  if (enabled) localStorage.setItem(enabledKey, 'true');
  else localStorage.removeItem(enabledKey);
}

export async function enableFocusReminder() {
  if (!supportsFocusReminder()) return 'unsupported' as const;
  const permission =
    Notification.permission === 'granted'
      ? 'granted'
      : await Notification.requestPermission();
  setFocusReminderEnabled(permission === 'granted');
  return permission;
}

export async function showFocusReminder({
  taskName,
  focusedSeconds,
  url,
}: {
  taskName: string;
  focusedSeconds: number;
  url: string;
}) {
  if (
    !supportsFocusReminder() ||
    Notification.permission !== 'granted' ||
    !readFocusReminderEnabled()
  )
    return false;

  const minutes = Math.max(1, Math.floor(focusedSeconds / 60));
  const options: NotificationOptions = {
    body: `你仍在专注「${taskName}」，已经 ${minutes} 分钟。记得在离开时暂停或结束。`,
    icon: appPath('pwa-192-v2.png'),
    badge: appPath('favicon.png'),
    tag: FOCUS_REMINDER_TAG,
    requireInteraction: true,
    data: { url },
  };

  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    if (registration) {
      await registration.showNotification('友间 · 专注仍在进行', options);
    } else {
      fallbackNotification?.close();
      fallbackNotification = new Notification('友间 · 专注仍在进行', options);
    }
    return true;
  } catch {
    return false;
  }
}

export async function closeFocusReminder() {
  fallbackNotification?.close();
  fallbackNotification = undefined;
  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    const notifications = await registration?.getNotifications({
      tag: FOCUS_REMINDER_TAG,
    });
    notifications?.forEach((notification) => notification.close());
  } catch {
    // Notification cleanup is best effort and must not affect focus controls.
  }
}
