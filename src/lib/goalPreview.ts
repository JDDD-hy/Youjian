import type { GoalType, PeriodType } from '../domain/types';

export function proposalSentence(
  goalType: GoalType,
  periodType: PeriodType,
  target: number,
) {
  const period = {
    daily: '1 个自然日内',
    weekly: '连续 7 天内',
    monthly: '连续一个月内',
  }[periodType];
  if (goalType === 'per_member_minutes') {
    const completion =
      periodType === 'daily'
        ? ''
        : periodType === 'weekly'
          ? '，7 天必须每天全部达标'
          : '，周期内必须每天全部达标';
    return `${period}，每位成员每天至少专注 ${target} 分钟${completion}。`;
  }
  if (goalType === 'shared_checkin_days')
    return `${period}，累计完成 ${target} 个全员打卡日；每个打卡日都要求所有成员达到空间每日目标。`;
  return `${period}，友间所有成员的专注时间合计达到 ${target} 分钟。`;
}

export function nextPeriodStart(
  period: PeriodType,
  timezone: string,
  now: Date = new Date(),
) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((part) => part.type === type)?.value);
  const date = new Date(Date.UTC(get('year'), get('month') - 1, get('day')));
  date.setUTCDate(date.getUTCDate() + 1);
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'UTC',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(date);
}

export function proposedPeriodLabel(
  period: PeriodType,
  timezone: string,
  now: Date = new Date(),
) {
  const start = nextPeriodStart(period, timezone, now);
  return `若今天全员通过，${start} 00:00 起${
    period === 'daily'
      ? '持续 1 天'
      : period === 'weekly'
        ? '持续 7 天'
        : '至下月同日'
  }`;
}
