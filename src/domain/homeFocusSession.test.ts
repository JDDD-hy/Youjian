import { describe, expect, it } from 'vitest';
import type { FocusSession, HomeSnapshot } from './types';
import { applyAuthoritativeFocusSession } from './homeFocusSession';

const activeSession = {
  session_id: 'session',
  status: 'focusing',
  category: 'work',
} as FocusSession;

const snapshot = { my_session: activeSession } as HomeSnapshot;

describe('applyAuthoritativeFocusSession', () => {
  it('applies the server-confirmed active category immediately', () => {
    const entertainment = {
      ...activeSession,
      category: 'entertainment',
    } as FocusSession;
    expect(
      applyAuthoritativeFocusSession(snapshot, entertainment).my_session,
    ).toBe(entertainment);
  });

  it('clears the matching active session after settlement', () => {
    const completed = {
      ...activeSession,
      status: 'completed',
    } as FocusSession;
    expect(
      applyAuthoritativeFocusSession(snapshot, completed).my_session,
    ).toBeNull();
  });
});
