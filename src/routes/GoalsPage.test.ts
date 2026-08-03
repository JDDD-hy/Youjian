import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  nextPeriodStart,
  proposalSentence,
  proposedPeriodLabel,
} from '../lib/goalPreview';

describe('goal proposal preview', () => {
  afterEach(() => vi.useRealTimers());

  it('renders a rolling weekly period from the day after acceptance', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-28T04:00:00Z'));
    expect(proposalSentence('per_member_minutes', 'weekly', 300)).toBe(
      '连续 7 天内，每位成员分别专注 300 分钟。',
    );
    expect(nextPeriodStart('weekly', 'Asia/Shanghai')).toBe('2026年7月29日');
    expect(proposedPeriodLabel('weekly', 'Asia/Shanghai')).toBe(
      '若今天全员通过，2026年7月29日 00:00 起持续 7 天',
    );
  });
});
