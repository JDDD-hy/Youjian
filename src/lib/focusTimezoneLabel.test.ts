import { describe, expect, it } from 'vitest';
import { focusTimezoneLabel } from './focusTimezoneLabel';

describe('focusTimezoneLabel', () => {
  it('shows the IANA timezone without a redundant local prefix', () => {
    expect(focusTimezoneLabel('Europe/Paris', 'Asia/Shanghai')).toBe(
      'Europe/Paris',
    );
  });

  it('stays hidden when the session and space use the same timezone', () => {
    expect(focusTimezoneLabel('Europe/Paris', 'Europe/Paris')).toBeUndefined();
  });
});
