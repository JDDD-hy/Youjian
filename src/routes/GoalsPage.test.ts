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
      '连续 7 天内，每位成员每天至少专注 300 分钟，7 天必须每天全部达标。',
    );
    expect(nextPeriodStart('weekly', 'Asia/Shanghai')).toBe('2026年7月29日');
    expect(proposedPeriodLabel('weekly', 'Asia/Shanghai')).toBe(
      '若今天全员通过，2026年7月29日 00:00 起持续 7 天',
    );
  });

  it.each([
    [
      'group_total_minutes',
      'daily',
      180,
      '1 个自然日内，友间所有成员的专注时间合计达到 180 分钟。',
    ],
    [
      'group_total_minutes',
      'weekly',
      180,
      '连续 7 天内，友间所有成员的专注时间合计达到 180 分钟。',
    ],
    [
      'group_total_minutes',
      'monthly',
      180,
      '连续一个月内，友间所有成员的专注时间合计达到 180 分钟。',
    ],
    [
      'per_member_minutes',
      'daily',
      180,
      '1 个自然日内，每位成员每天至少专注 180 分钟。',
    ],
    [
      'per_member_minutes',
      'weekly',
      180,
      '连续 7 天内，每位成员每天至少专注 180 分钟，7 天必须每天全部达标。',
    ],
    [
      'per_member_minutes',
      'monthly',
      180,
      '连续一个月内，每位成员每天至少专注 180 分钟，周期内必须每天全部达标。',
    ],
    [
      'shared_checkin_days',
      'daily',
      1,
      '1 个自然日内，累计完成 1 个全员打卡日；每个打卡日都要求所有成员达到空间每日目标。',
    ],
    [
      'shared_checkin_days',
      'weekly',
      3,
      '连续 7 天内，累计完成 3 个全员打卡日；每个打卡日都要求所有成员达到空间每日目标。',
    ],
    [
      'shared_checkin_days',
      'monthly',
      20,
      '连续一个月内，累计完成 20 个全员打卡日；每个打卡日都要求所有成员达到空间每日目标。',
    ],
  ] as const)(
    'states the complete %s/%s rule',
    (goalType, periodType, target, expected) => {
      expect(proposalSentence(goalType, periodType, target)).toBe(expected);
    },
  );
});
