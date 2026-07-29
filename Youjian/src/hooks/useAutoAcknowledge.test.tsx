import { renderHook } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { useAutoAcknowledge } from './useAutoAcknowledge';

describe('useAutoAcknowledge', () => {
  it('acknowledges each displayed id only once', () => {
    const acknowledge = vi.fn();
    const { rerender } = renderHook(
      ({ id }) => useAutoAcknowledge(id, acknowledge),
      { initialProps: { id: 'achievement-a' } },
    );

    expect(acknowledge).toHaveBeenCalledWith('achievement-a');
    rerender({ id: 'achievement-a' });
    expect(acknowledge).toHaveBeenCalledTimes(1);

    rerender({ id: 'achievement-b' });
    expect(acknowledge).toHaveBeenLastCalledWith('achievement-b');
    expect(acknowledge).toHaveBeenCalledTimes(2);
  });
});
