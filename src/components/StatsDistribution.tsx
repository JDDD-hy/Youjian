import type { CSSProperties } from 'react';
import type { StatsSummary } from '../domain/types';
import { formatDuration } from '../lib/format';

const MEMBER_COLORS = [
  '#8fbfda',
  '#dde2c2',
  '#e8b8c2',
  '#d8c6a5',
  '#a9c9c4',
  '#c6bfd8',
  '#e4c7aa',
  '#b7c8dc',
  '#d7bfcf',
  '#c7d8b5',
  '#e2d29f',
  '#b9c9c1',
] as const;

const HEAT_COLORS = ['#f1ece3', '#f7dfaa', '#edc86e', '#d7a62f', '#a97817'];

function colorForMember(index: number) {
  return MEMBER_COLORS[index % MEMBER_COLORS.length];
}

function shortDuration(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return hours ? `${hours}h ${rest}m` : `${minutes}m`;
}

function tooltipEdgeClass(index: number, count: number) {
  if (index === 0) return ' chart-tooltip--start';
  if (index === count - 1) return ' chart-tooltip--end';
  return '';
}

function DailyClock({ summary }: { summary: StatsSummary }) {
  const buckets = summary.hourly_buckets ?? [];
  const max = Math.max(
    ...buckets.map((item) => item.credited_focus_seconds),
    1,
  );
  const cx = 150;
  const cy = 150;
  const inner = 58;
  const outer = 116;

  return (
    <div className="focus-clock">
      <svg viewBox="0 0 300 300" role="img" aria-label="今日每小时专注分布">
        {[0, 6, 12, 18].map((hour) => {
          const angle = (hour / 24) * Math.PI * 2 - Math.PI / 2;
          const x = cx + Math.cos(angle) * 132;
          const y = cy + Math.sin(angle) * 132;
          return (
            <text
              key={hour}
              x={x}
              y={y}
              className="focus-clock__axis-label"
              textAnchor="middle"
              dominantBaseline="central"
            >
              {hour}
            </text>
          );
        })}
        {buckets.map((bucket) => {
          const angle = ((bucket.hour + 0.5) / 24) * Math.PI * 2 - Math.PI / 2;
          const length =
            8 + (bucket.credited_focus_seconds / max) * (outer - inner - 8);
          const x1 = cx + Math.cos(angle) * inner;
          const y1 = cy + Math.sin(angle) * inner;
          const x2 = cx + Math.cos(angle) * (inner + length);
          const y2 = cy + Math.sin(angle) * (inner + length);
          return (
            <line
              key={bucket.hour}
              x1={x1}
              y1={y1}
              x2={x2}
              y2={y2}
              className="focus-clock__bar"
              tabIndex={0}
            >
              <title>{`${String(bucket.hour).padStart(2, '0')}:00–${String(bucket.hour + 1).padStart(2, '0')}:00 · ${formatDuration(bucket.credited_focus_seconds)}`}</title>
            </line>
          );
        })}
        <circle cx={cx} cy={cy} r="48" className="focus-clock__center" />
        <text
          x={cx}
          y={cy - 7}
          textAnchor="middle"
          className="focus-clock__center-label"
        >
          今日
        </text>
        <text
          x={cx}
          y={cy + 17}
          textAnchor="middle"
          className="focus-clock__center-value"
        >
          {shortDuration(summary.credited_focus_seconds)}
        </text>
      </svg>
    </div>
  );
}

function WeekBars({ summary }: { summary: StatsSummary }) {
  const members = summary.members ?? [];
  const colors = new Map(
    members.map((member, index) => [member.member_id, colorForMember(index)]),
  );
  const max = Math.max(
    ...summary.days.map((day) => day.credited_focus_seconds),
    1,
  );
  return (
    <div className="week-chart" role="img" aria-label="本周各成员每日专注贡献">
      {summary.days.map((day, dayIndex) => (
        <div className="week-chart__day" key={day.local_date}>
          <div className="week-chart__track">
            {(day.member_contributions ?? []).map((contribution) => (
              <span
                key={contribution.member_id}
                className="week-chart__segment"
                style={{
                  height: `${(contribution.credited_focus_seconds / max) * 100}%`,
                  background: colors.get(contribution.member_id),
                }}
                tabIndex={0}
              >
                <span
                  className={`chart-tooltip${tooltipEdgeClass(dayIndex, summary.days.length)}`}
                >
                  {contribution.display_name} ·{' '}
                  {formatDuration(contribution.credited_focus_seconds)}
                </span>
              </span>
            ))}
          </div>
          <small>
            {new Intl.DateTimeFormat('zh-CN', {
              timeZone: 'UTC',
              weekday: 'short',
            }).format(new Date(`${day.local_date}T12:00:00Z`))}
          </small>
        </div>
      ))}
    </div>
  );
}

function MonthHeatmap({ summary }: { summary: StatsSummary }) {
  const monthPrefix = summary.anchor_local_date.slice(0, 7);
  const recordedDays = summary.days.filter(
    (day) =>
      day.local_date.startsWith(`${monthPrefix}-`) &&
      day.local_date <= summary.anchor_local_date,
  );
  const recordedByDate = new Map(
    recordedDays.map((day) => [day.local_date, day]),
  );
  const year = Number(monthPrefix.slice(0, 4));
  const month = Number(monthPrefix.slice(5, 7));
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const monthNumber = Number(monthPrefix.slice(5, 7));
  const calendarDays = Array.from({ length: daysInMonth }, (_, index) => {
    const dayOfMonth = index + 1;
    const localDate = `${monthPrefix}-${String(dayOfMonth).padStart(2, '0')}`;
    return {
      dayOfMonth,
      localDate,
      recorded: recordedByDate.get(localDate),
      isFuture: localDate > summary.anchor_local_date,
    };
  });
  const max = Math.max(
    ...recordedDays.map((day) => day.credited_focus_seconds),
    1,
  );
  const firstWeekday =
    (new Date(`${monthPrefix}-01T12:00:00Z`).getUTCDay() + 6) % 7;
  const weekCount = Math.ceil((firstWeekday + daysInMonth) / 7);
  return (
    <div className="month-heatmap-wrap">
      <div className="month-heatmap__weekdays" aria-hidden="true">
        {['一', '二', '三', '四', '五', '六', '日'].map((day) => (
          <span key={day}>{day}</span>
        ))}
      </div>
      <div
        className="month-heatmap"
        role="img"
        aria-label="本月每日专注热力图"
        style={{ '--month-week-count': weekCount } as CSSProperties}
      >
        {calendarDays.map(({ dayOfMonth, localDate, recorded, isFuture }) => {
          const gridIndex = firstWeekday + dayOfMonth - 1;
          const weekIndex = Math.floor(gridIndex / 7);
          const seconds = isFuture
            ? 0
            : (recorded?.credited_focus_seconds ?? 0);
          const ratio = seconds / max;
          const level =
            seconds === 0 ? 0 : Math.min(4, Math.max(1, Math.ceil(ratio * 4)));
          return (
            <span
              key={localDate}
              className={`month-heatmap__cell${isFuture ? ' month-heatmap__cell--future' : ''}`}
              style={{
                background: HEAT_COLORS[level],
                gridColumn: weekIndex + 1,
                gridRow: (gridIndex % 7) + 1,
              }}
              tabIndex={0}
              aria-label={
                isFuture
                  ? `${localDate}，尚未到来`
                  : `${localDate}，专注 ${formatDuration(seconds)}`
              }
            >
              <span
                className={`chart-tooltip${tooltipEdgeClass(weekIndex, weekCount)}`}
              >
                {monthNumber}/{dayOfMonth} ·{' '}
                {isFuture ? '尚未到来' : formatDuration(seconds)}
              </span>
            </span>
          );
        })}
      </div>
    </div>
  );
}

export function StatsDistribution({ summary }: { summary: StatsSummary }) {
  const members = summary.members ?? [];
  const memberColors = members.map((member, index) => ({
    ...member,
    color: colorForMember(index),
  }));
  return (
    <>
      <div className="section-heading chart-heading">
        <h2 id="trend-title">专注分布</h2>
        {summary.period === 'weekly' && (
          <div className="member-legend" aria-label="成员颜色图例">
            {memberColors.map((member) => (
              <span key={member.member_id}>
                <i style={{ background: member.color }} />
                {member.display_name}
              </span>
            ))}
          </div>
        )}
        {summary.period === 'monthly' && (
          <span className="month-heading-label">
            {Number(summary.anchor_local_date.slice(5, 7))}月
          </span>
        )}
      </div>
      {summary.period === 'daily' ? (
        <DailyClock summary={summary} />
      ) : summary.period === 'weekly' ? (
        <WeekBars summary={summary} />
      ) : (
        <MonthHeatmap summary={summary} />
      )}
      <p className="timezone-note">
        按 {summary.timezone} 的自然日统计，仅包含已经结束并计入统计的专注。
      </p>
    </>
  );
}

export { MEMBER_COLORS };
