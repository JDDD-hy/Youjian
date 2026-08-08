import { describe, expect, it } from 'vitest';
import type { FocusSession } from '../domain/types';
import { calculateFocusSeconds } from './useServerClock';

const base: FocusSession = {
  session_id: 'session',
  space_id: 'space',
  member_id: 'member',
  task_name: '阅读',
  category: 'reading',
  task_history: [],
  status: 'focusing',
  started_at: '2026-07-27T06:00:00.000Z',
  timezone_snapshot: 'UTC',
  accumulated_focus_seconds: 300,
  active_segment_started_at: '2026-07-27T06:10:00.000Z',
  paused_at: null,
  auto_settle_at: null,
  completed_at: null,
  completion_reason: null,
  credited_focus_seconds: null,
  counts_toward_stats: null,
};

describe('calculateFocusSeconds', () => {
  it('adds only the active segment to accumulated server time', () => {
    expect(
      calculateFocusSeconds(base, Date.parse('2026-07-27T06:12:30.000Z')),
    ).toBe(450);
  });
  it('does not add wall time while paused', () => {
    expect(
      calculateFocusSeconds(
        {
          ...base,
          status: 'paused',
          active_segment_started_at: null,
          accumulated_focus_seconds: 420,
        },
        Date.parse('2026-07-27T08:00:00.000Z'),
      ),
    ).toBe(420);
  });
  it('uses final credited seconds after settlement', () => {
    expect(
      calculateFocusSeconds(
        {
          ...base,
          status: 'completed',
          active_segment_started_at: null,
          credited_focus_seconds: 600,
        },
        Date.parse('2026-07-27T09:00:00.000Z'),
      ),
    ).toBe(600);
  });
});
