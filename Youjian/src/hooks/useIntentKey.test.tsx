import { renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { useIntentKey } from './useIntentKey';

describe('useIntentKey', () => {
  it('reuses a key for retries and rotates it for a new intent', () => {
    const { result } = renderHook(() => useIntentKey());
    const first = result.current.get('pause:session-1');
    expect(result.current.get('pause:session-1')).toBe(first);
    expect(result.current.get('resume:session-1')).not.toBe(first);
  });
});
