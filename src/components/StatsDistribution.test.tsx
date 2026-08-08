import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { StatsSummary } from '../domain/types';
import { MEMBER_COLORS, StatsDistribution } from './StatsDistribution';

const base: StatsSummary = {
  space_id: 'space',
  view: 'space',
  period: 'weekly',
  timezone: 'Asia/Shanghai',
  period_start: '2026-08-02T16:00:00Z',
  period_end: '2026-08-09T16:00:00Z',
  anchor_local_date: '2026-08-08',
  credited_focus_seconds: 3600,
  valid_session_count: 3,
  checkin_day_count: 0,
  members: [
    { member_id: 'ju', display_name: 'JU' },
    { member_id: 'claudia', display_name: 'claudia' },
    { member_id: 'jade', display_name: 'jade' },
  ],
  days: [
    {
      local_date: '2026-08-03',
      credited_focus_seconds: 3600,
      checkin_completed: false,
      member_contributions: [
        { member_id: 'ju', display_name: 'JU', credited_focus_seconds: 1800 },
        {
          member_id: 'claudia',
          display_name: 'claudia',
          credited_focus_seconds: 1200,
        },
        {
          member_id: 'jade',
          display_name: 'jade',
          credited_focus_seconds: 600,
        },
      ],
    },
  ],
};

describe('StatsDistribution', () => {
  it('shows member contribution durations and assigns colors by join order', () => {
    const { container } = render(<StatsDistribution summary={base} />);
    expect(screen.getByText('JU · 30 分钟')).toBeInTheDocument();
    const dots = [
      ...container.querySelectorAll('.member-legend i'),
    ] as HTMLElement[];
    expect(MEMBER_COLORS.slice(0, 4)).toEqual([
      '#8fbfda',
      '#dde2c2',
      '#e8b8c2',
      '#d8c6a5',
    ]);
    expect(dots.map((dot) => dot.style.background)).toEqual([
      'rgb(143, 191, 218)',
      'rgb(221, 226, 194)',
      'rgb(232, 184, 194)',
    ]);
  });

  it('lays out the complete current month and keeps future dates empty', () => {
    const { container } = render(
      <StatsDistribution
        summary={{
          ...base,
          period: 'monthly',
          days: [
            {
              local_date: '2026-08-08',
              credited_focus_seconds: 60,
              checkin_completed: false,
            },
            {
              local_date: '2026-08-09',
              credited_focus_seconds: 60,
              checkin_completed: false,
            },
            {
              local_date: '2026-07-31',
              credited_focus_seconds: 60,
              checkin_completed: false,
            },
          ],
        }}
      />,
    );
    expect(screen.getByLabelText(/2026-08-08/)).toBeInTheDocument();
    expect(screen.getByLabelText('2026-08-09，尚未到来')).toBeInTheDocument();
    expect(screen.queryByLabelText(/2026-07-31/)).not.toBeInTheDocument();
    expect(screen.getByText('8月')).toBeInTheDocument();
    expect(screen.getByText(/8\/8 · 1 分钟/)).toBeInTheDocument();
    expect(screen.getByText('8/9 · 尚未到来')).toBeInTheDocument();
    expect(container.querySelectorAll('.month-heatmap__cell')).toHaveLength(31);
    expect(container.querySelector('.month-heatmap')).toHaveStyle({
      '--month-week-count': '6',
    });
    expect(screen.getByLabelText(/2026-08-01/)).toHaveStyle({
      gridColumn: '1',
      gridRow: '6',
    });
    expect(screen.getByLabelText(/2026-08-31/)).toHaveStyle({
      gridColumn: '6',
      gridRow: '1',
    });
    expect(
      screen.getByLabelText(/2026-08-31/).querySelector('.chart-tooltip--end'),
    ).toBeInTheDocument();
  });
});
