import { describe, expect, it, vi } from 'vitest';
import { ApiError } from './api';

vi.mock('./supabase', () => ({
  getSupabaseClient: () => ({
    rpc: vi.fn(() => Promise.resolve({ data: null, error: null })),
  }),
}));

describe('safe error reporting', () => {
  it('redacts invite tokens and raw error messages', async () => {
    window.history.replaceState({}, '', '/invite/very-secret-token');
    const { buildSafeErrorReport } = await import('./safeError');
    const report = buildSafeErrorReport(
      new Error('nickname Alice task secret token abc'),
      'window_error',
    );
    expect(report.route).toBe('/invite/:token');
    expect(JSON.stringify(report)).not.toContain('Alice');
    expect(JSON.stringify(report)).not.toContain('secret');
  });

  it('redacts a project-pages invite token', async () => {
    const { safeRoute } = await import('./safeError');
    expect(safeRoute('/Youjian/invite/very-secret-token')).toBe(
      '/invite/:token',
    );
  });

  it('keeps only stable ApiError codes', async () => {
    const { buildSafeErrorReport } = await import('./safeError');
    expect(
      buildSafeErrorReport(new ApiError('SPACE_FULL'), 'react').errorCode,
    ).toBe('SPACE_FULL');
    expect(
      buildSafeErrorReport(new ApiError('unsafe raw value'), 'react').errorCode,
    ).toBe('UNEXPECTED_CLIENT_ERROR');
  });
});
