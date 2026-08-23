import { describe, expect, it } from 'vitest';
import { resolveLampVariant } from './lampVariant';

describe('resolveLampVariant', () => {
  it.each([
    ['idle', 'entertainment', 'idle'],
    ['focusing', 'study', 'focusing'],
    ['focusing', 'life', 'focusing'],
    ['focusing', 'entertainment', 'entertainment-focusing'],
    ['paused', 'entertainment', 'paused'],
    ['paused', 'study', 'paused'],
  ] as const)('maps %s and %s to %s', (state, category, expected) => {
    expect(resolveLampVariant(state, category)).toBe(expected);
  });

  it('falls back to the regular focusing lamp for an unknown category', () => {
    expect(resolveLampVariant('focusing', 'future-category')).toBe('focusing');
  });
});
