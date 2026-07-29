import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from './api';
import { assertRouteSpace } from './spaceBoundary';

const reportSafeError = vi.hoisted(() => vi.fn());

vi.mock('./safeError', () => ({ reportSafeError }));

describe('assertRouteSpace', () => {
  beforeEach(() => reportSafeError.mockReset());

  it('accepts data from the routed space', () => {
    expect(() => assertRouteSpace('space-a', 'space-a', 'test')).not.toThrow();
    expect(reportSafeError).not.toHaveBeenCalled();
  });

  it('reports and rejects data from another space', () => {
    let thrown: unknown;
    try {
      assertRouteSpace('space-a', 'space-b', 'test');
    } catch (error) {
      thrown = error;
    }
    expect(thrown).toBeInstanceOf(ApiError);
    expect((thrown as ApiError).code).toBe('CROSS_SPACE_RESPONSE');
    expect(reportSafeError).toHaveBeenCalledOnce();
  });
});
