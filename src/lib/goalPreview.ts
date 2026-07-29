import type { GoalType, PeriodType } from '../domain/types';

export function proposalSentence(
  goalType: GoalType,
  periodType: PeriodType,
  target: number,
) {
  const unit = goalType === 'shared_checkin_days' ? '天' : '分钟';
  const period = { daily: '自然日', weekly: '周', monthly: '月' }[periodType];
  if (goalType === 'per_member_minutes')
    return `下一个完整${period}，每位成员分别专注 ${target} ${unit}。`;
  if (goalType === 'shared_checkin_days')
    return `下一个完整${period}，所有成员共同完成 ${target} 个打卡日。`;
  return `下一个完整${period}，友间成员合计专注 ${target} ${unit}。`;
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
  if (period === 'daily') date.setUTCDate(date.getUTCDate() + 1);
  else if (period === 'weekly') {
    const day = date.getUTCDay();
    date.setUTCDate(date.getUTCDate() + (day === 1 ? 7 : (8 - day) % 7));
  } else date.setUTCMonth(date.getUTCMonth() + 1, 1);
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'UTC',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(date);
}
