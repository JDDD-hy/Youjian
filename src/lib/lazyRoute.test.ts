import { describe, expect, it } from 'vitest';
import { isChunkLoadError } from './lazyRoute';

describe('isChunkLoadError', () => {
  it.each([
    'Failed to fetch dynamically imported module: /assets/GoalsPage-old.js',
    'Importing a module script failed',
    'Loading chunk GoalsPage failed',
  ])('recognizes stale deployment chunks: %s', (message) => {
    expect(isChunkLoadError(new TypeError(message))).toBe(true);
  });

  it('does not reload for ordinary route errors', () => {
    expect(isChunkLoadError(new Error('permission denied'))).toBe(false);
  });
});
