import { describe, expect, it } from 'vitest';
import { recoveryCodesText } from './recoveryCodes';

describe('recoveryCodesText', () => {
  it('creates a portable plain-text recovery bundle', () => {
    const text = recoveryCodesText(
      ['first_code', 'second_code'],
      'Claudia',
      '2026-08-08T10:00:00Z',
    );
    expect(text).toContain('身份昵称：Claudia');
    expect(text).toContain('1. first_code');
    expect(text).toContain('2. second_code');
    expect(text).toContain('每个恢复码只能使用一次');
  });
});
