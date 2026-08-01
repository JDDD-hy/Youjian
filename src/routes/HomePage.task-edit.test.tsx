import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { FocusSession } from '../domain/types';
import { EditTaskDrawer, TaskHistory } from './HomePage';

const session: FocusSession = {
  session_id: 'session',
  space_id: 'space',
  member_id: 'member',
  task_name: '新任务',
  category: 'work',
  task_history: [],
  status: 'focusing',
  started_at: '2026-08-01T08:00:00.000Z',
  accumulated_focus_seconds: 60,
  active_segment_started_at: '2026-08-01T08:00:00.000Z',
  paused_at: null,
  auto_settle_at: '2026-08-01T14:00:00.000Z',
  completed_at: null,
  completion_reason: null,
  credited_focus_seconds: null,
  counts_toward_stats: null,
};

describe('focus task editing', () => {
  it('reveals previous sticky-note versions on demand', () => {
    render(
      <TaskHistory
        history={[
          {
            task_name: '旧任务',
            category: 'study',
            changed_at: '2026-08-01T08:30:00.000Z',
          },
        ]}
      />,
    );
    const toggle = screen.getByRole('button', { name: /查看旧任务/ });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByText('旧任务')).not.toBeInTheDocument();
    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByText('旧任务')).toBeVisible();
    expect(screen.getByText(/学习.*修改于/)).toBeVisible();
  });

  it('prefills the current values and submits a changed task', () => {
    const onSave = vi.fn();
    render(
      <EditTaskDrawer
        session={session}
        pending={false}
        onClose={vi.fn()}
        onSave={onSave}
      />,
    );
    const input = screen.getByRole('textbox', { name: /任务名称/ });
    expect(input).toHaveValue('新任务');
    const save = screen.getByRole('button', { name: '保存修改' });
    expect(save).toBeDisabled();
    fireEvent.change(input, { target: { value: '更新后的任务' } });
    fireEvent.click(save);
    expect(onSave).toHaveBeenCalledWith('更新后的任务', 'work');
  });
});
