import { describe, expect, it } from 'vitest';
import { isoDateInTimezone, splitSegmentsByLocalDate } from './format';

describe('isoDateInTimezone', () => {
  it('derives the local date in the selected backend timezone', () => {
    const instant = new Date('2026-07-27T16:30:00.000Z');
    expect(isoDateInTimezone('Asia/Shanghai', instant)).toBe('2026-07-28');
    expect(isoDateInTimezone('America/New_York', instant)).toBe('2026-07-27');
  });
});

describe('splitSegmentsByLocalDate', () => {
  it('splits a segment at local midnight without losing elapsed time', () => {
    expect(
      splitSegmentsByLocalDate(
        [
          {
            started_at: '2026-07-27T15:50:00.000Z',
            ended_at: '2026-07-27T16:20:00.000Z',
          },
        ],
        'Asia/Shanghai',
      ),
    ).toEqual([
      { local_date: '2026-07-27', credited_focus_seconds: 600 },
      { local_date: '2026-07-28', credited_focus_seconds: 1200 },
    ]);
  });

  it('uses actual elapsed time across a daylight-saving boundary', () => {
    expect(
      splitSegmentsByLocalDate(
        [
          {
            started_at: '2026-03-28T23:30:00.000Z',
            ended_at: '2026-03-29T01:30:00.000Z',
          },
        ],
        'Europe/Paris',
      ).reduce((total, item) => total + item.credited_focus_seconds, 0),
    ).toBe(7200);
  });
});
