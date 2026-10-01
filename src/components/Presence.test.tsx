import { act, fireEvent, render, screen } from '@testing-library/react';
import { StrictMode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Presence } from './Presence';
import { AccessibleModal } from './AccessibleModal';

function motion(enabled: boolean) {
  vi.stubGlobal('matchMedia', () => ({
    matches: enabled,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }));
}

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('Presence', () => {
  it('keeps removed rows inert until exit finishes, without changing list markup', async () => {
    motion(true);
    vi.useFakeTimers();
    const list = (keys: string[]) => (
      <StrictMode>
        <ul>
          <Presence>
            {keys.map((key) => (
              <li key={key}>{key}</li>
            ))}
          </Presence>
        </ul>
      </StrictMode>
    );
    const { rerender } = render(list(['a', 'b']));
    const first = screen.getByText('a');
    expect(first.parentElement?.tagName).toBe('UL');
    rerender(list(['b', 'c']));
    expect(first).toHaveAttribute('inert');
    expect(first).toHaveAttribute('aria-hidden', 'true');
    expect(screen.getAllByRole('listitem')).toHaveLength(2);
    await act(() => vi.advanceTimersByTime(250));
    expect(first).not.toBeInTheDocument();
    expect(screen.getByText('c')).toBeInTheDocument();
  });

  it('keeps the same node and fresh content when a key returns during exit', async () => {
    motion(true);
    vi.useFakeTimers();
    const { rerender } = render(
      <Presence>
        <button key="item">Before</button>
      </Presence>,
    );
    const button = screen.getByRole('button');
    rerender(<Presence>{null}</Presence>);
    rerender(
      <Presence>
        <button key="item">After</button>
      </Presence>,
    );
    await act(() => vi.advanceTimersByTime(250));
    expect(screen.getByRole('button', { name: 'After' })).toBe(button);
    expect(button).not.toHaveAttribute('inert');
    expect(button).not.toHaveAttribute('aria-hidden');
  });

  it('removes content immediately when reduced motion is requested', () => {
    motion(false);
    const { rerender } = render(
      <Presence>
        <p>Notice</p>
      </Presence>,
    );
    rerender(<Presence>{null}</Presence>);
    expect(screen.queryByText('Notice')).not.toBeInTheDocument();
  });

  it('restores modal focus and releases its keyboard handler before visual exit', async () => {
    motion(true);
    vi.useFakeTimers();
    const close = vi.fn();
    const trigger = document.createElement('button');
    document.body.append(trigger);
    trigger.focus();
    const { rerender } = render(
      <Presence>
        <AccessibleModal titleId="presence-title" onClose={close}>
          <h2 id="presence-title">Motion dialog</h2>
          <button data-autofocus>Confirm</button>
        </AccessibleModal>
      </Presence>,
    );
    const dialog = screen.getByRole('dialog');
    expect(screen.getByRole('button', { name: 'Confirm' })).toHaveFocus();
    rerender(<Presence>{null}</Presence>);
    expect(dialog).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(close).not.toHaveBeenCalled();
    await act(() => vi.advanceTimersByTime(250));
    expect(dialog).not.toBeInTheDocument();
    trigger.remove();
  });
});
