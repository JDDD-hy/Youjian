import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { FocusSession } from '../domain/types';
import { FocusHealthCheckModal } from './FocusHealthCheckModal';

const session: FocusSession = {
  session_id: 'health-session',
  space_id: 'space',
  member_id: 'member',
  task_name: '整理分类体系',
  category: 'study',
  task_history: [],
  status: 'focusing',
  started_at: '2026-08-11T00:00:00Z',
  timezone_snapshot: 'Asia/Shanghai',
  accumulated_focus_seconds: 7200,
  active_segment_started_at: '2026-08-11T00:00:00Z',
  paused_at: null,
  auto_settle_at: '2026-08-11T02:01:00Z',
  completed_at: null,
  completion_reason: null,
  credited_focus_seconds: null,
  counts_toward_stats: null,
};

describe('FocusHealthCheckModal', () => {
  afterEach(cleanup);
  it('shows an explicit countdown and only the two valid choices', () => {
    const onEnd = vi.fn();
    const onContinue = vi.fn();
    render(
      <FocusHealthCheckModal
        session={session}
        remainingSeconds={47}
        pending={false}
        onEnd={onEnd}
        onContinue={onContinue}
      />,
    );

    expect(screen.getByText('47')).toBeVisible();
    expect(screen.getByText('秒后自动结束')).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: '收起此刻' }));
    fireEvent.click(screen.getByRole('button', { name: '我想继续专注' }));
    expect(onEnd).toHaveBeenCalledOnce();
    expect(onContinue).toHaveBeenCalledOnce();
    expect(screen.queryByRole('button', { name: /关闭|取消/ })).toBeNull();
  });

  it('disables choices at the authoritative deadline', () => {
    render(
      <FocusHealthCheckModal
        session={session}
        remainingSeconds={0}
        pending={false}
        onEnd={vi.fn()}
        onContinue={vi.fn()}
      />,
    );
    expect(screen.getByRole('button', { name: '收起此刻' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '我想继续专注' })).toBeDisabled();
  });
});
