import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { FocusSession } from '../domain/types';
import {
  FOCUS_REMINDER_DELAY_MS,
  FOCUS_REMINDER_REPEAT_INTERVAL_MS,
  FOCUS_REMINDER_SECOND_DELAY_MS,
  PAUSED_FOCUS_WARNING_DELAY_MS,
  getFocusReminderResetKey,
  getFocusReminderDelay,
  releaseFocusReminder,
  reserveFocusReminder,
} from '../lib/focusReminder';
import { FocusReminder } from './FocusReminder';

const session: FocusSession = {
  session_id: 'session-1',
  space_id: 'space-1',
  member_id: 'member-1',
  task_name: '阅读论文',
  category: 'reading',
  task_history: [],
  status: 'focusing',
  started_at: '2026-08-10T00:00:00.000Z',
  timezone_snapshot: 'Asia/Shanghai',
  accumulated_focus_seconds: 600,
  active_segment_started_at: new Date(Date.now() - 10 * 60_000).toISOString(),
  paused_at: null,
  auto_settle_at: null,
  completed_at: null,
  completion_reason: null,
  credited_focus_seconds: null,
  counts_toward_stats: null,
};

function pausedSession(pausedAt = Date.now()): FocusSession {
  return {
    ...session,
    status: 'paused',
    active_segment_started_at: null,
    paused_at: new Date(pausedAt).toISOString(),
    auto_settle_at: new Date(pausedAt + 15 * 60_000).toISOString(),
  };
}

describe('FocusReminder', () => {
  const notification =
    vi.fn<(title: string, options?: NotificationOptions) => void>();
  let permission: NotificationPermission;
  let visibility: DocumentVisibilityState;

  beforeEach(() => {
    vi.useFakeTimers();
    localStorage.clear();
    permission = 'default';
    visibility = 'visible';
    notification.mockClear();

    class MockNotification {
      static get permission() {
        return permission;
      }
      static requestPermission = vi.fn(() => {
        permission = 'granted';
        return Promise.resolve(permission);
      });
      close = vi.fn();
      constructor(title: string, options?: NotificationOptions) {
        notification(title, options);
      }
    }
    Object.defineProperty(window, 'Notification', {
      configurable: true,
      value: MockNotification,
    });
    vi.spyOn(document, 'hasFocus').mockReturnValue(true);
    vi.spyOn(document, 'visibilityState', 'get').mockImplementation(
      () => visibility,
    );
  });

  afterEach(async () => {
    cleanup();
    await Promise.resolve();
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('enables reminders after the user grants notification permission', async () => {
    render(<FocusReminder session={session} />);

    fireEvent.click(screen.getByRole('button', { name: '开启提醒' }));
    await act(() => Promise.resolve());

    expect(localStorage.getItem('youjian:focus-reminder-enabled')).toBe('true');
    expect(screen.getByText(/离开后按 2\/30\/90 分钟提醒/)).toBeVisible();
  });

  it('notifies after an enabled focus stays in the background for two minutes', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });

    expect(notification).toHaveBeenCalled();
    const [title, options] = notification.mock.calls.at(-1) ?? [];
    expect(title).toBe('友间 · 专注仍在进行');
    expect(options?.body).toContain('阅读论文');
    expect(options?.body).toContain('页面已离开 2 分钟');
    expect(options?.body).toContain('本次累计');
    expect(options?.requireInteraction).toBe(true);
  });

  it('warns once after focus has stayed paused in the background for ten minutes', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const pausedAt = Date.now();
    render(<FocusReminder session={pausedSession(pausedAt)} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(PAUSED_FOCUS_WARNING_DELAY_MS - 1);
    });
    expect(notification).not.toHaveBeenCalled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(notification).toHaveBeenCalledTimes(1);
    const [title, options] = notification.mock.calls[0] ?? [];
    expect(title).toBe('友间 · 专注即将自动结束');
    expect(options?.body).toContain('已暂停 10 分钟');
    expect(options?.body).toContain('约 5 分钟后自动结束');

    await act(async () => {
      await vi.advanceTimersByTimeAsync(5 * 60_000);
    });
    expect(notification).toHaveBeenCalledTimes(1);
  });

  it('keeps the paused warning deadline across snapshot refreshes', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const paused = pausedSession();
    const { rerender } = render(<FocusReminder session={paused} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5 * 60_000);
    });
    rerender(
      <FocusReminder session={{ ...paused, accumulated_focus_seconds: 900 }} />,
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5 * 60_000);
    });

    expect(notification).toHaveBeenCalledTimes(1);
  });

  it('cancels the paused warning after focus resumes', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const { rerender } = render(<FocusReminder session={pausedSession()} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(9 * 60_000);
    });
    visibility = 'visible';
    document.dispatchEvent(new Event('visibilitychange'));
    rerender(<FocusReminder session={session} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10 * 60_000);
    });

    expect(notification).not.toHaveBeenCalled();
  });

  it('does not send a stale warning after the auto-settle deadline', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const pausedAt = Date.now();
    render(<FocusReminder session={pausedSession(pausedAt)} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    vi.setSystemTime(pausedAt + 16 * 60_000);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(PAUSED_FOCUS_WARNING_DELAY_MS);
    });

    expect(notification).not.toHaveBeenCalled();
  });

  it('cancels a paused warning on return and uses the original deadline if away again', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    render(<FocusReminder session={pausedSession()} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(9 * 60_000);
    });
    visibility = 'visible';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2 * 60_000);
    });
    expect(notification).not.toHaveBeenCalled();

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(notification).toHaveBeenCalledTimes(1);
  });

  it('starts a fresh paused warning timeline for a new pause episode', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const { rerender } = render(<FocusReminder session={pausedSession()} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(PAUSED_FOCUS_WARNING_DELAY_MS);
    });
    expect(notification).toHaveBeenCalledTimes(1);

    visibility = 'visible';
    document.dispatchEvent(new Event('visibilitychange'));
    rerender(<FocusReminder session={session} />);
    const nextPaused = pausedSession(Date.now());
    rerender(<FocusReminder session={nextPaused} />);
    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(PAUSED_FOCUS_WARNING_DELAY_MS);
    });

    expect(notification).toHaveBeenCalledTimes(2);
  });

  it('keeps the absolute reminder timeline when the session snapshot refreshes', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const { rerender } = render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });

    rerender(
      <FocusReminder
        session={{ ...session, accumulated_focus_seconds: 720 }}
      />,
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(
        FOCUS_REMINDER_SECOND_DELAY_MS - FOCUS_REMINDER_DELAY_MS,
      );
    });

    expect(notification).toHaveBeenCalledTimes(2);
  });

  it('notifies at 2, 30, 90, and 150 minutes without intermediate repeats', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));

    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });
    expect(notification).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(
        FOCUS_REMINDER_SECOND_DELAY_MS - FOCUS_REMINDER_DELAY_MS - 1,
      );
    });
    expect(notification).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(notification).toHaveBeenCalledTimes(2);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_REPEAT_INTERVAL_MS);
    });
    expect(notification).toHaveBeenCalledTimes(3);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_REPEAT_INTERVAL_MS);
    });
    expect(notification).toHaveBeenCalledTimes(4);
  });

  it('coalesces missed reminder points after a heavily throttled timer', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    render(<FocusReminder session={session} />);

    visibility = 'hidden';
    const awayStartedAt = Date.now();
    document.dispatchEvent(new Event('visibilitychange'));
    vi.setSystemTime(awayStartedAt + getFocusReminderDelay(3));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });

    expect(notification).toHaveBeenCalledTimes(1);
  });

  it('cancels the timeline when another tab returns to the page', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(
      new StorageEvent('storage', {
        key: getFocusReminderResetKey(session.session_id),
        newValue: 'another-tab-returned',
      }),
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(getFocusReminderDelay(3));
    });

    expect(notification).not.toHaveBeenCalled();
  });

  it('allows one new reminder after the user returns and leaves again', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });

    visibility = 'visible';
    document.dispatchEvent(new Event('visibilitychange'));
    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });

    expect(notification).toHaveBeenCalledTimes(2);
  });

  it('cancels and resets a pending reminder when focus pauses', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const { rerender } = render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    rerender(<FocusReminder session={{ ...session, status: 'paused' }} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });

    expect(notification).not.toHaveBeenCalled();
  });

  it('releases the session reservation when focus pauses', async () => {
    permission = 'granted';
    localStorage.setItem('youjian:focus-reminder-enabled', 'true');
    const { rerender } = render(<FocusReminder session={session} />);

    visibility = 'hidden';
    document.dispatchEvent(new Event('visibilitychange'));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(FOCUS_REMINDER_DELAY_MS);
    });
    rerender(<FocusReminder session={{ ...session, status: 'paused' }} />);

    expect(reserveFocusReminder(session.session_id, 0)).toBeDefined();
  });

  it('reserves a reminder once across tabs until the away cycle resets', () => {
    const firstToken = reserveFocusReminder(session.session_id, 0);

    expect(firstToken).toBeDefined();
    expect(reserveFocusReminder(session.session_id, 0)).toBeUndefined();
    expect(reserveFocusReminder(session.session_id, 1)).toBeDefined();

    releaseFocusReminder(session.session_id, firstToken);
    expect(reserveFocusReminder(session.session_id, 2)).toBeDefined();
  });
});
