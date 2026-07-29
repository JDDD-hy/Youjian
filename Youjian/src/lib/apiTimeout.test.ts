import { afterEach, describe, expect, it, vi } from 'vitest';
import { withRequestTimeout } from './api';

describe('withRequestTimeout', () => {
  afterEach(() => vi.useRealTimers());

  it('rejects requests that remain pending past the deadline', async () => {
    vi.useFakeTimers();
    const pending = withRequestTimeout(
      new Promise<never>(() => undefined),
      100,
    );
    const rejection = expect(pending).rejects.toMatchObject({
      code: 'REQUEST_TIMEOUT',
    });

    await vi.advanceTimersByTimeAsync(100);
    await rejection;
  });
});
