import type {
  CompletionReason,
  FocusCategory,
  GoalType,
  PeriodType,
} from '../domain/types';

export const categoryLabels: Record<FocusCategory, string> = {
  study: '学习',
  work: '工作',
  reading: '阅读',
  exercise: '运动',
  other: '其他',
};

export const goalTypeLabels: Record<GoalType, string> = {
  group_total_minutes: '小组合计',
  per_member_minutes: '每人门槛',
  shared_checkin_days: '共同出勤',
};

export const periodLabels: Record<PeriodType, string> = {
  daily: '每日',
  weekly: '每周',
  monthly: '每月',
};

export const completionLabels: Record<CompletionReason, string> = {
  manual_end: '主动结束',
  pause_timeout: '暂停满 15 分钟自动结束',
  focus_limit: '达到 6 小时上限自动结束',
  member_disabled: '成员停用时结束',
};

export function formatDuration(totalSeconds: number, withSeconds = false) {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  const seconds = safe % 60;
  if (withSeconds) {
    return [hours, minutes, seconds]
      .map((value) => String(value).padStart(2, '0'))
      .join(':');
  }
  if (hours) return `${hours} 小时 ${minutes} 分钟`;
  return `${minutes} 分钟`;
}

export function formatLocalDateTime(value: string, timezone?: string) {
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: timezone,
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
}

export function getDeviceTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Shanghai';
}

export function todayIsoDate() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

export function isoDateInTimezone(timezone: string, date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

export function splitSegmentsByLocalDate(
  segments: Array<{ started_at: string; ended_at: string | null }>,
  timezone: string,
) {
  const totals = new Map<string, number>();
  const add = (date: string, milliseconds: number) =>
    totals.set(date, (totals.get(date) ?? 0) + Math.max(0, milliseconds));
  for (const segment of segments) {
    if (!segment.ended_at) continue;
    const start = Date.parse(segment.started_at);
    const end = Date.parse(segment.ended_at);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start)
      continue;
    const startDate = isoDateInTimezone(timezone, new Date(start));
    const endDate = isoDateInTimezone(timezone, new Date(end - 1));
    if (startDate === endDate) {
      add(startDate, end - start);
      continue;
    }
    let low = start;
    let high = end;
    while (high - low > 1) {
      const middle = Math.floor((low + high) / 2);
      if (isoDateInTimezone(timezone, new Date(middle)) === startDate)
        low = middle;
      else high = middle;
    }
    add(startDate, high - start);
    add(endDate, end - high);
  }
  return [...totals.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([local_date, milliseconds]) => ({
      local_date,
      credited_focus_seconds: Math.floor(milliseconds / 1000),
    }));
}
