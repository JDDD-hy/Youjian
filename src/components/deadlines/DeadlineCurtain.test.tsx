import '@testing-library/jest-dom/vitest';
import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DeadlineCurtain } from './DeadlineCurtain';

const deadline = {
  id: 'deadline-id',
  title: '法考',
  target_date: '2026-11-06',
  created_at: '2026-08-15T00:00:00Z',
  updated_at: '2026-08-15T00:00:00Z',
};

afterEach(cleanup);

describe('DeadlineCurtain', () => {
  it('exposes a real toggle button while keeping the sheet mounted', async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    render(
      <DeadlineCurtain
        open={false}
        onOpenChange={onOpenChange}
        deadline={deadline}
        dayState={{ kind: 'future', days: 83, label: '83 天' }}
        onEdit={vi.fn()}
      />,
    );
    const toggle = screen.getByRole('button', { name: '展开倒数日幕布' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByLabelText('个人倒数日')).toHaveAttribute(
      'aria-hidden',
      'true',
    );
    await user.click(toggle);
    expect(onOpenChange).toHaveBeenCalledWith(true);
  });

  it('shows the single deadline and opens editing from the cloth', async () => {
    const user = userEvent.setup();
    const onEdit = vi.fn();
    render(
      <DeadlineCurtain
        open
        onOpenChange={vi.fn()}
        deadline={deadline}
        dayState={{ kind: 'future', days: 83, label: '83 天' }}
        onEdit={onEdit}
      />,
    );
    expect(screen.getByText('83 天')).toBeVisible();
    await user.click(screen.getByRole('button', { name: '修改倒数日：法考' }));
    expect(onEdit).toHaveBeenCalledOnce();
  });

  it('renders a retry state without removing the curtain', async () => {
    const user = userEvent.setup();
    const onRetry = vi.fn();
    render(
      <DeadlineCurtain
        open
        onOpenChange={vi.fn()}
        deadline={null}
        dayState={null}
        error
        onRetry={onRetry}
        onEdit={vi.fn()}
      />,
    );
    expect(screen.getByText('暂时无法读取倒数日')).toBeVisible();
    await user.click(screen.getByRole('button', { name: '重试' }));
    expect(onRetry).toHaveBeenCalledOnce();
  });
});
