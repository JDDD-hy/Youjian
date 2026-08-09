import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  STATS_QUERY_RETRY_COUNT,
  statsQueryRetryDelay,
} from '../lib/statsRetry';
import { StatsPage } from './StatsPage';

const rpc = vi.hoisted(() => vi.fn());
vi.mock('../lib/api', () => ({ rpc }));

function mount() {
  const router = createMemoryRouter(
    [{ path: '/space/:spaceId/stats', element: <StatsPage /> }],
    { initialEntries: ['/space/space/stats'] },
  );
  return render(
    <QueryClientProvider
      client={
        new QueryClient({ defaultOptions: { queries: { retry: false } } })
      }
    >
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
}

describe('StatsPage session detail', () => {
  beforeEach(() => {
    rpc.mockReset();
    rpc.mockImplementation((name: string) => {
      if (name === 'get_home_snapshot')
        return Promise.resolve({
          data: {
            me: { profile_timezone: 'Asia/Shanghai' },
            space: { id: 'space', timezone: 'Asia/Shanghai' },
          },
          serverNow: '2026-07-28T04:00:00Z',
        });
      if (name === 'get_stats_summary')
        return Promise.resolve({
          data: {
            space_id: 'space',
            timezone: 'Asia/Shanghai',
            period_start: '2026-07-27T16:00:00Z',
            period_end: '2026-08-03T16:00:00Z',
            credited_focus_seconds: 600,
            valid_session_count: 1,
            checkin_day_count: 0,
            anchor_local_date: '2026-07-28',
            members: [{ member_id: 'member', display_name: '小友' }],
            hourly_buckets: [],
            days: [],
          },
        });
      if (name === 'list_focus_history')
        return Promise.resolve({
          data: {
            space_id: 'space',
            items: [
              {
                session_id: 'session',
                member: { member_id: 'member', display_name: '小友' },
                task_name: '阅读论文',
                category: 'reading',
                started_at: '2026-07-28T01:00:00Z',
                completed_at: '2026-07-28T01:10:00Z',
                credited_focus_seconds: 600,
                status: 'completed',
                completion_reason: 'manual_end',
                counts_toward_stats: true,
                unconfirmed_connection_seconds: 30,
              },
            ],
            next_cursor: null,
          },
        });
      if (name === 'get_focus_session_detail')
        return Promise.resolve({
          data: {
            session: { space_id: 'space' },
            segments: [
              {
                started_at: '2026-07-28T01:00:00Z',
                ended_at: '2026-07-28T01:10:00Z',
              },
            ],
            connection_unconfirmed_intervals: [
              {
                started_at: '2026-07-28T01:05:00Z',
                ended_at: '2026-07-28T01:05:30Z',
                detected_from_last_seen_at: '2026-07-28T01:03:00Z',
              },
            ],
            settlement: { reason: 'manual_end', counts_toward_stats: true },
          },
        });
      throw new Error(`Unexpected RPC ${name}`);
    });
  });

  it('loads authoritative segments and connection intervals on demand', async () => {
    mount();
    fireEvent.click(await screen.findByRole('button', { name: /阅读论文/ }));
    expect(
      await screen.findByRole('heading', { name: '专注分段' }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { name: '连接不可确认区间' }),
    ).toBeInTheDocument();
    expect(rpc).toHaveBeenCalledWith('get_focus_session_detail', {
      session_id: 'session',
    });
  });

  it('opens the Chinese week/month export chooser from history heading', async () => {
    mount();
    fireEvent.click(await screen.findByRole('button', { name: '数据导出' }));

    expect(
      screen.getByRole('heading', { name: '数据导出' }),
    ).toBeInTheDocument();
    const dialogs = screen.getAllByRole('dialog');
    const dialog = dialogs[dialogs.length - 1]!;
    expect(within(dialog).getByRole('button', { name: '周' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(
      within(dialog).getByRole('button', { name: '月' }),
    ).toBeInTheDocument();
    const weekPicker = within(dialog).getByLabelText('选择周日期');
    expect(weekPicker).toHaveAttribute('type', 'date');
    const showPicker = vi.fn();
    Object.defineProperty(weekPicker, 'showPicker', {
      configurable: true,
      value: showPicker,
    });
    fireEvent.click(within(dialog).getByRole('button', { name: /^选择周：/ }));
    expect(showPicker).toHaveBeenCalledOnce();
    fireEvent.change(weekPicker, {
      target: { value: '2026-07-15' },
    });
    expect(within(dialog).getByText('7/13 ~ 7/19')).toBeInTheDocument();
    fireEvent.click(within(dialog).getByRole('button', { name: '月' }));
    expect(within(dialog).getByText('2026年8月')).toBeInTheDocument();
    expect(
      within(dialog).getByRole('button', { name: '导出 Markdown' }),
    ).toBeInTheDocument();
  });
});

describe('StatsPage transient failure recovery', () => {
  it('keeps retrying read-only stats requests through the schema-cache convergence window', () => {
    expect(STATS_QUERY_RETRY_COUNT).toBe(4);
    expect([0, 1, 2, 3, 4].map(statsQueryRetryDelay)).toEqual([
      1_000, 2_000, 4_000, 4_000, 4_000,
    ]);
  });
});
