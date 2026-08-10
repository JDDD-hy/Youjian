import { appPath } from './appBase';

export const FOCUS_REMINDER_DELAY_MS = 2 * 60 * 1000;
export const FOCUS_REMINDER_SECOND_DELAY_MS = 30 * 60 * 1000;
export const FOCUS_REMINDER_REPEAT_INTERVAL_MS = 60 * 60 * 1000;
export const FOCUS_REMINDER_TAG = 'youjian-active-focus';

const enabledKey = 'youjian:focus-reminder-enabled';
const claimKeyPrefix = 'youjian:focus-reminder-claim:';
const resetKeyPrefix = 'youjian:focus-reminder-reset:';
let fallbackNotification: Notification | undefined;

function claimKey(sessionId: string) {
  return `${claimKeyPrefix}${sessionId}`;
}

export function getFocusReminderResetKey(sessionId: string) {
  return `${resetKeyPrefix}${sessionId}`;
}

export function announceFocusReminderReset(sessionId: string) {
  try {
    const key = getFocusReminderResetKey(sessionId);
    localStorage.setItem(
      key,
      `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`,
    );
    localStorage.removeItem(key);
  } catch {
    // Cross-tab reset is best effort when storage is unavailable.
  }
}

type ReminderClaim = {
  reminderIndex: number;
  token: string;
};

function readReminderClaim(key: string): ReminderClaim | undefined {
  const value = localStorage.getItem(key);
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value) as Partial<ReminderClaim>;
    if (
      typeof parsed.reminderIndex === 'number' &&
      typeof parsed.token === 'string'
    ) {
      return { reminderIndex: parsed.reminderIndex, token: parsed.token };
    }
  } catch {
    // A malformed or legacy claim can be replaced safely.
  }
  return undefined;
}

export function getFocusReminderDelay(reminderIndex: number) {
  if (reminderIndex <= 0) return FOCUS_REMINDER_DELAY_MS;
  return (
    FOCUS_REMINDER_SECOND_DELAY_MS +
    (reminderIndex - 1) * FOCUS_REMINDER_REPEAT_INTERVAL_MS
  );
}

export function reserveFocusReminder(sessionId: string, reminderIndex: number) {
  const token =
    globalThis.crypto?.randomUUID?.() ??
    `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;

  try {
    const key = claimKey(sessionId);
    const existing = readReminderClaim(key);
    if (existing && existing.reminderIndex >= reminderIndex) return undefined;
    localStorage.setItem(key, JSON.stringify({ reminderIndex, token }));
    return readReminderClaim(key)?.token === token ? token : undefined;
  } catch {
    // Storage can be unavailable in privacy modes. Single-tab deduplication
    // still works in the component, so allow the reminder to continue.
    return token;
  }
}

export function releaseFocusReminder(sessionId: string, token?: string) {
  try {
    const key = claimKey(sessionId);
    if (token && readReminderClaim(key)?.token !== token) return;
    localStorage.removeItem(key);
  } catch {
    // Reservation cleanup is best effort.
  }
}

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
