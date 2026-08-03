import type { GoalType, PeriodType } from '../domain/types';

export function proposalSentence(
  goalType: GoalType,
  periodType: PeriodType,
  target: number,
) {
  const unit = goalType === 'shared_checkin_days' ? '天' : '分钟';
  const period = {
    daily: '1 个自然日',
    weekly: '连续 7 天',
    monthly: '连续一个月',
  }[periodType];
  if (goalType === 'per_member_minutes')
    return `${period}内，每位成员分别专注 ${target} ${unit}。`;
  if (goalType === 'shared_checkin_days')
    return `${period}内，所有成员共同完成 ${target} 个打卡日。`;
  return `${period}内，友间成员合计专注 ${target} ${unit}。`;
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
