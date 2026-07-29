import { useEffect, useMemo, useState } from 'react';
import type { FocusSession } from '../domain/types';

export function calculateFocusSeconds(session: FocusSession, nowMs: number) {
  if (session.status !== 'focusing' || !session.active_segment_started_at) {
    return session.credited_focus_seconds ?? session.accumulated_focus_seconds;
  }
  return Math.max(
    session.accumulated_focus_seconds,
    session.accumulated_focus_seconds +
      Math.floor(
        (nowMs - Date.parse(session.active_segment_started_at)) / 1000,
      ),
  );
}

export function useServerClock(serverNow?: string, receivedAt?: number) {
  const base = receivedAt ?? (serverNow ? Date.parse(serverNow) : 0);
  const offset = useMemo(
    () => (serverNow ? Date.parse(serverNow) - base : 0),
    [base, serverNow],
  );
  const [now, setNow] = useState(base + offset);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now() + offset), 1000);
    return () => window.clearInterval(timer);
  }, [offset]);
  return now;
}
