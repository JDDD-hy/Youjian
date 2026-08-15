export type DeadlineDayState =
  | { kind: 'future'; days: number; label: string }
  | { kind: 'today'; days: 0; label: '就是今天' }
  | { kind: 'past'; days: number; label: '' };

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

export function localDateValue(date = new Date()): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function dateOrdinal(value: string): number | null {
  const match = DATE_PATTERN.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const timestamp = Date.UTC(year, month - 1, day);
  const parsed = new Date(timestamp);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return Math.floor(timestamp / 86_400_000);
}

export function deadlineDayState(
  targetDate: string,
  today = localDateValue(),
): DeadlineDayState {
  const target = dateOrdinal(targetDate);
  const current = dateOrdinal(today);
  if (target === null || current === null) {
    return { kind: 'past', days: -1, label: '' };
  }
  const days = target - current;
  if (days > 0) return { kind: 'future', days, label: `${days} 天` };
  if (days === 0) return { kind: 'today', days: 0, label: '就是今天' };
  return { kind: 'past', days, label: '' };
}

export function millisecondsUntilNextLocalDay(now = new Date()): number {
  const next = new Date(now);
  next.setHours(24, 0, 0, 0);
  return Math.max(1, next.getTime() - now.getTime());
}

export function formatDeadlineDate(value: string): string {
  const match = DATE_PATTERN.exec(value);
  if (!match || dateOrdinal(value) === null) return value;
  return `${Number(match[1])} 年 ${Number(match[2])} 月 ${Number(match[3])} 日`;
}
