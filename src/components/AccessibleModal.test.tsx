import { fireEvent, render, screen } from '@testing-library/react';
import { useState } from 'react';
import { describe, expect, it } from 'vitest';
import { AccessibleModal } from './AccessibleModal';

function Harness() {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button onClick={() => setOpen(true)}>打开</button>
      {open && (
        <AccessibleModal titleId="modal-title" onClose={() => setOpen(false)}>
          <h2 id="modal-title">测试对话框</h2>
          <button data-autofocus>确认</button>
          <button>取消</button>
        </AccessibleModal>
      )}
    </>
  );
}

describe('AccessibleModal', () => {
  it('focuses inside, closes with Escape and restores trigger focus', () => {
    render(<Harness />);
    const trigger = screen.getByRole('button', { name: '打开' });
    trigger.focus();
    fireEvent.click(trigger);
    expect(screen.getByRole('button', { name: '确认' })).toHaveFocus();
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
  });
});
