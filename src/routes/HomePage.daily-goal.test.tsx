import '@testing-library/jest-dom/vitest';
import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DailyGoalDrawer } from './HomePage';

const today = {
  local_date: '2026-08-04',
  credited_focus_seconds: 0,
  checkin_target_seconds: 3600,
  checkin_completed: false,
  current_streak_days: 0,
  goal_target_minutes: 60,
  goal_source: 'space_default' as const,
  goal_locked: false,
  future_default_target_minutes: 60,
};

afterEach(cleanup);

describe('DailyGoalDrawer', () => {
  it('rejects targets below thirty minutes', async () => {
    const user = userEvent.setup();
    render(
      <DailyGoalDrawer
        today={today}
        pending={false}
        onClose={vi.fn()}
        onSave={vi.fn()}
      />,
    );
    const input = screen.getByLabelText('目标时长（分钟）');
    await user.clear(input);
    await user.type(input, '29');
    expect(screen.getByText('请输入30–720之间的整数分钟。')).toBeVisible();
    expect(screen.getByRole('button', { name: '保存目标' })).toBeDisabled();
  });

  it('saves a today-only override before focus starts', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(
      <DailyGoalDrawer
        today={today}
        pending={false}
        onClose={vi.fn()}
        onSave={onSave}
      />,
    );
    const input = screen.getByLabelText('目标时长（分钟）');
    await user.clear(input);
    await user.type(input, '45');
    await user.click(screen.getByRole('button', { name: '保存目标' }));
    expect(onSave).toHaveBeenCalledWith('today', 45);
  });

  it('locks today but allows the future default', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(
      <DailyGoalDrawer
        today={{ ...today, goal_locked: true }}
        pending={false}
        onClose={vi.fn()}
        onSave={onSave}
      />,
    );
    expect(screen.getByLabelText('仅修改今天')).toBeDisabled();
    expect(screen.getByLabelText('从明天起每天重复')).toBeChecked();
    await user.click(screen.getByRole('button', { name: '保存目标' }));
    expect(onSave).toHaveBeenCalledWith('future_default', 60);
  });
});
