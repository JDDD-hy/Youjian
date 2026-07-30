import { describe, expect, it } from 'vitest';
import { inviteInputToUrl, normalizeInviteUrl } from './inviteUrl';

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

describe('inviteInputToUrl', () => {
  it('accepts a raw invite token', () => {
    const token = 'B'.repeat(43);
    expect(inviteInputToUrl(token, 'https://youjian.example')).toBe(
      `https://youjian.example/invite/${token}`,
    );
  });

  it('rejects text that is neither a token nor an invite URL', () => {
    expect(inviteInputToUrl('hello', 'https://youjian.example')).toBeNull();
  });
});
