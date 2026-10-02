import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react';
import type { PropsWithChildren } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRoomRealtime } from './useRoomRealtime';
import { scheduleRoomRefresh } from '../lib/roomRefresh';

const realtime = vi.hoisted(() => ({
  channels: [] as Array<{
    handlers: Record<string, () => void>;
    subscribe: (callback: (status: string) => void) => unknown;
    status?: (status: string) => void;
  }>,
  removeChannel: vi.fn(() => Promise.resolve()),
}));
const loadMembership = vi.hoisted(() => vi.fn());
const onlineState = vi.hoisted(() => ({ value: true }));

vi.mock('../lib/membership', () => ({ loadMembership }));
vi.mock('./useOnlineStatus', () => ({
  useOnlineStatus: () => onlineState.value,
}));
vi.mock('../lib/supabase', () => ({
  getSupabaseClient: () => ({
    channel: () => {
      const item = {
        handlers: {} as Record<string, () => void>,
        subscribe(callback: (status: string) => void) {
          item.status = callback;
          return item;
        },
        status: undefined as ((status: string) => void) | undefined,
        on(_kind: string, filter: { table: string }, callback: () => void) {
          item.handlers[filter.table] = callback;
          return item;
        },
      };
      realtime.channels.push(item);
      return item;
    },
    removeChannel: realtime.removeChannel,
  }),
}));

function createWrapper(client: QueryClient) {
  return function Wrapper({ children }: PropsWithChildren) {
    return (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    );
  };
}

describe('useRoomRealtime', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  beforeEach(() => {
    realtime.channels.length = 0;
    realtime.removeChannel.mockClear();
    loadMembership.mockReset();
    onlineState.value = true;
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
  });

  it('treats navigator offline as a hint until a request also fails', () => {
    onlineState.value = false;
    const client = new QueryClient();
    const { result, rerender } = renderHook(
      ({ failed }) => useRoomRealtime('space', Number.MAX_SAFE_INTEGER, failed),
      {
        initialProps: { failed: false },
        wrapper: createWrapper(client),
      },
    );
    expect(result.current).toBe('unconfirmed');
    rerender({ failed: true });
    expect(result.current).toBe('offline');
  });

  it('coalesces heartbeat and realtime bursts without starving later updates', () => {
    vi.useFakeTimers();
    const client = new QueryClient();
    const invalidate = vi.spyOn(client, 'invalidateQueries');
    renderHook(() => useRoomRealtime('space', Number.MAX_SAFE_INTEGER), {
      wrapper: createWrapper(client),
    });

    act(() => {
      scheduleRoomRefresh(client, 'space', ['home']);
      realtime.channels[0]?.handlers.focus_sessions?.();
      realtime.channels[0]?.handlers.goals?.();
      realtime.channels[0]?.handlers.achievements?.();
      vi.advanceTimersByTime(90);
      realtime.channels[0]?.handlers.focus_sessions?.();
    });
    expect(invalidate).not.toHaveBeenCalled();
    act(() => {
      vi.advanceTimersByTime(10);
    });
    expect(invalidate.mock.calls.map(([filter]) => filter?.queryKey)).toEqual([
      ['home', 'space'],
      ['goals', 'space'],
      ['achievements', 'space'],
      ['personal-achievements', 'space'],
      ['nav-notifications', 'space'],
      ['settings', 'space'],
    ]);

    act(() => {
      realtime.channels[0]?.handlers.focus_sessions?.();
      vi.advanceTimersByTime(100);
    });
    expect(invalidate).toHaveBeenCalledTimes(12);
  });

  it('keeps refresh batches separate for different rooms and clients', () => {
    vi.useFakeTimers();
    const first = new QueryClient();
    const second = new QueryClient();
    const firstRefresh = vi.spyOn(first, 'invalidateQueries');
    const secondRefresh = vi.spyOn(second, 'invalidateQueries');
    scheduleRoomRefresh(first, 'one', ['home']);
    scheduleRoomRefresh(first, 'two', ['home']);
    scheduleRoomRefresh(second, 'one', ['home']);
    vi.advanceTimersByTime(100);
    expect(firstRefresh.mock.calls.map(([filter]) => filter?.queryKey)).toEqual(
      [
        ['home', 'one'],
        ['home', 'two'],
      ],
    );
    expect(secondRefresh).toHaveBeenCalledExactlyOnceWith({
      queryKey: ['home', 'one'],
    });
  });

  it('re-subscribes after returning from the background', async () => {
    const client = new QueryClient();
    const { result } = renderHook(
      () => useRoomRealtime('space', Number.MAX_SAFE_INTEGER),
      { wrapper: createWrapper(client) },
    );
    const initialChannelCount = realtime.channels.length;
    act(() => realtime.channels.at(-1)?.status?.('SUBSCRIBED'));
    expect(result.current).toBe('connected');

    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'hidden',
    });
    void act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    expect(result.current).toBe('unconfirmed');

    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    void act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await waitFor(() =>
      expect(realtime.channels.length).toBeGreaterThan(initialChannelCount),
    );
    act(() => realtime.channels.at(-1)?.status?.('SUBSCRIBED'));
    expect(result.current).toBe('connected');
    expect(realtime.removeChannel).toHaveBeenCalled();
  });

  it('clears room caches when membership becomes inactive', async () => {
    const client = new QueryClient();
    client.setQueryData(['home', 'space'], { value: true });
    client.setQueryData(['settings', 'space'], { value: true });
    loadMembership.mockResolvedValue({
      membership: null,
      latest_disabled_membership: { space_name: 'room' },
    });
    renderHook(() => useRoomRealtime('space', Number.MAX_SAFE_INTEGER), {
      wrapper: createWrapper(client),
    });
    act(() => realtime.channels[0]?.handlers.space_members?.());
    await waitFor(() =>
      expect(client.getQueryData(['home', 'space'])).toBeUndefined(),
    );
    expect(client.getQueryData(['settings', 'space'])).toBeUndefined();
    expect(client.getQueryData(['membership'])).toEqual(
      expect.objectContaining({ membership: null }),
    );
  });
});
