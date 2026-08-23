import type { FocusSession, HomeSnapshot } from './types';

export function applyAuthoritativeFocusSession(
  snapshot: HomeSnapshot,
  session: FocusSession,
): HomeSnapshot {
  const active = session.status === 'focusing' || session.status === 'paused';
  if (active) return { ...snapshot, my_session: session };
  if (snapshot.my_session?.session_id === session.session_id)
    return { ...snapshot, my_session: null };
  return snapshot;
}
