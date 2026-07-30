import { describe, expect, it } from 'vitest';
import { normalizeInviteUrl } from './inviteUrl';

const token = 'A'.repeat(43);

describe('normalizeInviteUrl', () => {
  it('re-homes an absolute server URL onto the current public origin', () => {
    expect(
      normalizeInviteUrl(
        `http://localhost:5173/invite/${token}`,
        'https://jddd-hy.github.io',
      ),
    ).toBe(`https://jddd-hy.github.io/invite/${token}`);
  });

  it('resolves relative invite paths and rejects unrelated paths', () => {
    expect(normalizeInviteUrl(`/invite/${token}`, 'https://example.com')).toBe(
      `https://example.com/invite/${token}`,
    );
    expect(
      normalizeInviteUrl(`/settings/${token}`, 'https://example.com'),
    ).toBe(null);
  });
});
