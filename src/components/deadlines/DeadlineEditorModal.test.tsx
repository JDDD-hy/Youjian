import '@testing-library/jest-dom/vitest';
import { cleanup, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { localDateValue } from '../../domain/deadlineDate';
import { DeadlineEditorModal } from './DeadlineEditorModal';

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('DeadlineEditorModal', () => {
  it('starts blank, validates input, and saves a trimmed title', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(undefined);
    const onClose = vi.fn();
    render(
      <DeadlineEditorModal
        deadline={null}
        pending={false}
        onSave={onSave}
        onClose={onClose}
      />,
    );
    const save = screen.getByRole('button', { name: '保存倒数日' });
    expect(screen.getByPlaceholderText('例如：你的Deadline')).toHaveValue('');
    expect(save).toBeDisabled();
    await user.type(screen.getByRole('textbox', { name: /目标/ }), '  法考  ');
    const today = localDateValue();
    await user.type(screen.getByLabelText('日期'), today);
    await user.click(save);
    expect(onSave).toHaveBeenCalledWith({
      title: '法考',
      targetDate: today,
    });
    expect(onClose).toHaveBeenCalledOnce();
    vi.useRealTimers();
  });

  it('asks before Escape discards dirty values', async () => {
    const user = userEvent.setup();
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const onClose = vi.fn();
    render(
      <DeadlineEditorModal
        deadline={null}
        pending={false}
        onSave={vi.fn()}
        onClose={onClose}
      />,
    );
    await user.type(screen.getByRole('textbox', { name: /目标/ }), '法考');
    await user.keyboard('{Escape}');
    expect(confirm).toHaveBeenCalledWith('放弃修改？');
    expect(onClose).not.toHaveBeenCalled();
  });

  it('retains values when server-confirmed saving fails', async () => {
    const user = userEvent.setup();
    render(
      <DeadlineEditorModal
        deadline={null}
        pending={false}
        onSave={vi.fn().mockRejectedValue(new Error('保存失败'))}
        onClose={vi.fn()}
      />,
    );
    await user.type(screen.getByRole('textbox', { name: /目标/ }), '法考');
    await user.type(screen.getByLabelText('日期'), '2099-08-16');
    await user.click(screen.getByRole('button', { name: '保存倒数日' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('保存失败');
    expect(screen.getByRole('textbox', { name: /目标/ })).toHaveValue('法考');
    vi.useRealTimers();
  });
});
