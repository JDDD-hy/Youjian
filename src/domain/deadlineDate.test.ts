import { describe, expect, it } from 'vitest';
import {
  deadlineDayState,
  formatDeadlineDate,
  localDateValue,
  millisecondsUntilNextLocalDay,
} from './deadlineDate';

describe('deadlineDate', () => {
  it('distinguishes a future date, today, and an expired date', () => {
    expect(deadlineDayState('2026-08-18', '2026-08-15')).toEqual({
      kind: 'future',
      days: 3,
      label: '3 天',
    });
    expect(deadlineDayState('2026-08-15', '2026-08-15')).toEqual({
      kind: 'today',
      days: 0,
      label: '就是今天',
    });
    expect(deadlineDayState('2026-08-14', '2026-08-15')).toMatchObject({
      kind: 'past',
      label: '',
    });
  });

  it('uses calendar ordinals across month and DST boundaries', () => {
    expect(deadlineDayState('2026-04-01', '2026-03-31')).toMatchObject({
      days: 1,
    });
    expect(deadlineDayState('2026-11-02', '2026-11-01')).toMatchObject({
      days: 1,
    });
  });

  it('builds local date values and schedules the next local midnight', () => {
    const now = new Date(2026, 7, 15, 23, 59, 59, 500);
    expect(localDateValue(now)).toBe('2026-08-15');
    expect(millisecondsUntilNextLocalDay(now)).toBe(500);
    expect(formatDeadlineDate('2026-08-15')).toBe('2026 年 8 月 15 日');
  });
});
