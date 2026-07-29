import { afterEach, describe, expect, it, vi } from 'vitest';
import { nextPeriodStart, proposalSentence } from '../lib/goalPreview';

describe('goal proposal preview', () => {
  afterEach(() => vi.useRealTimers());

  it('renders a complete sentence and the next full weekly period', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-28T04:00:00Z'));
    expect(proposalSentence('per_member_minutes', 'weekly', 300)).toBe(
      '下一个完整周，每位成员分别专注 300 分钟。',
    );
    expect(nextPeriodStart('weekly', 'Asia/Shanghai')).toBe('2026年8月3日');
  });
});
