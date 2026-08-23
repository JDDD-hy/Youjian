import { describe, expect, it } from 'vitest';
import type {
  FocusSessionDetail,
  HistoryItem,
  StatsSummary,
} from '../domain/types';
import { buildFocusExport, sessionOverlapsPeriod } from './focusExport';

const history: HistoryItem = {
  session_id: '00000000-0000-4000-8000-000000000001',
  member: {
    member_id: '00000000-0000-4000-8000-000000000002',
    display_name: '不应导出',
  },
  task_name: 'Write taxonomy',
  category: 'work',
  started_at: '2026-08-03T00:10:00Z',
  completed_at: '2026-08-03T01:10:00Z',
  credited_focus_seconds: 3000,
  status: 'completed',
  completion_reason: 'manual_end',
  counts_toward_stats: true,
  unconfirmed_connection_seconds: 0,
};

const detail: FocusSessionDetail = {
  session: {
    session_id: history.session_id,
    space_id: '00000000-0000-4000-8000-000000000003',
    member_id: history.member.member_id,
    task_name: history.task_name,
    category: history.category,
    task_history: [
      {
        task_name: 'Read taxonomy',
        category: 'reading',
        changed_at: '2026-08-03T00:30:00Z',
      },
    ],
    status: 'completed',
    started_at: history.started_at,
    timezone_snapshot: 'UTC',
    accumulated_focus_seconds: 3000,
    active_segment_started_at: null,
    paused_at: null,
    auto_settle_at: null,
    completed_at: history.completed_at,
    completion_reason: 'manual_end',
    credited_focus_seconds: 3000,
    counts_toward_stats: true,
  },
  segments: [
    {
      started_at: '2026-08-03T00:10:00Z',
      ended_at: '2026-08-03T00:40:00Z',
    },
    {
      started_at: '2026-08-03T00:50:00Z',
      ended_at: '2026-08-03T01:10:00Z',
    },
  ],
  connection_unconfirmed_intervals: [],
  settlement: { reason: 'manual_end', counts_toward_stats: true },
};

const summary: StatsSummary = {
  space_id: detail.session.space_id,
  view: 'mine',
  period: 'weekly',
  timezone: 'UTC',
  period_start: '2026-08-03T00:00:00Z',
  period_end: '2026-08-10T00:00:00Z',
  credited_focus_seconds: 3000,
  valid_session_count: 1,
  checkin_day_count: 0,
  anchor_local_date: '2026-08-03',
  members: [],
  days: [
    {
      local_date: '2026-08-03',
      credited_focus_seconds: 3000,
      checkin_completed: false,
    },
  ],
};

describe('focus Markdown export', () => {
  it('exports life and entertainment categories in the task dictionary', async () => {
    const categorizedDetail: FocusSessionDetail = {
      ...detail,
      session: {
        ...detail.session,
        category: 'entertainment',
        task_history: [
          {
            task_name: 'Tidy room',
            category: 'life',
            changed_at: '2026-08-03T00:30:00Z',
          },
        ],
      },
    };
    const result = await buildFocusExport({
      period: 'weekly',
      summary,
      space: { id: detail.session.space_id, name: 'Research room' },
      memberId: history.member.member_id,
      sessions: [
        {
          history: {
            ...history,
            task_name: 'Play a game',
            category: 'entertainment',
          },
          detail: categorizedDetail,
        },
      ],
      exportedAt: '2026-08-10T00:00:01Z',
      dataUntil: '2026-08-10T00:00:01Z',
    });

    expect(result.content).toMatch(/\tlife\tTidy room/);
    expect(result.content).toMatch(/\tentertainment\tPlay a game/);
  });

  it('builds a compact English, self-contained and privacy-scoped report', async () => {
    const result = await buildFocusExport({
      period: 'weekly',
      summary,
      space: { id: detail.session.space_id, name: 'Research room' },
      memberId: history.member.member_id,
      sessions: [{ history, detail }],
      exportedAt: '2026-08-10T00:00:01Z',
      dataUntil: '2026-08-10T00:00:01Z',
    });

    expect(result.filename).toBe('youjian-focus-week-2026-08-03.md');
    expect(result.content).toContain('schema: youjian.focus-export');
    expect(result.content).toContain('period_status: complete');
    expect(result.content).toContain('| effective_focus | 3000 | 0:50:00 |');
    expect(result.content).toContain('| elapsed | 3600 | 1:00:00 |');
    expect(result.content).toContain('| paused | 600 | 0:10:00 |');
    expect(result.content).toContain('Read taxonomy');
    expect(result.content).toContain('Write taxonomy');
    expect(result.content).not.toContain(history.session_id);
    expect(result.content).not.toContain(history.member.display_name);
    expect(result.eventsSha256).toMatch(/^[a-f0-9]{64}$/);
  });

  it('marks current ranges partial and preserves empty periods', async () => {
    const result = await buildFocusExport({
      period: 'weekly',
      summary: {
        ...summary,
        credited_focus_seconds: 0,
        valid_session_count: 0,
      },
      space: { id: detail.session.space_id, name: 'Research room' },
      memberId: history.member.member_id,
      sessions: [],
      exportedAt: '2026-08-04T00:00:00Z',
      dataUntil: '2026-08-04T00:00:00Z',
    });

    expect(result.filename).toBe('youjian-focus-week-2026-08-03_partial.md');
    expect(result.content).toContain('period_status: partial');
    expect(result.content).toContain('record_count: 0');
  });

  it('detects sessions whose focus segments cross a period boundary', () => {
    expect(
      sessionOverlapsPeriod(
        {
          ...detail,
          segments: [
            {
              started_at: '2026-08-02T23:50:00Z',
              ended_at: '2026-08-03T00:20:00Z',
            },
          ],
        },
        summary.period_start,
        summary.period_end,
      ),
    ).toBe(true);
  });

  it('refuses to export a summary and raw snapshot that disagree', async () => {
    await expect(
      buildFocusExport({
        period: 'weekly',
        summary: { ...summary, credited_focus_seconds: 1 },
        space: { id: detail.session.space_id, name: 'Research room' },
        memberId: history.member.member_id,
        sessions: [{ history, detail }],
        exportedAt: '2026-08-10T00:00:01Z',
        dataUntil: '2026-08-10T00:00:01Z',
      }),
    ).rejects.toThrow('FOCUS_EXPORT_INCONSISTENT_SNAPSHOT');
  });

  it('matches the database by flooring each local day before summing', async () => {
    const fractionalDetail: FocusSessionDetail = {
      ...detail,
      segments: [
        {
          started_at: '2026-08-03T23:59:58.400Z',
          ended_at: '2026-08-04T00:00:01.600Z',
        },
      ],
    };
    const result = await buildFocusExport({
      period: 'weekly',
      summary: {
        ...summary,
        credited_focus_seconds: 2,
        days: [
          {
            local_date: '2026-08-03',
            credited_focus_seconds: 1,
            checkin_completed: false,
          },
          {
            local_date: '2026-08-04',
            credited_focus_seconds: 1,
            checkin_completed: false,
          },
        ],
      },
      space: { id: detail.session.space_id, name: 'Research room' },
      memberId: history.member.member_id,
      sessions: [{ history, detail: fractionalDetail }],
      exportedAt: '2026-08-04T01:00:00Z',
      dataUntil: '2026-08-04T01:00:00Z',
    });

    expect(result.content).toContain('| effective_focus | 2 | 0:00:02 |');
    expect(result.content).not.toContain('\n+schema:');
  });

  it('preserves mixed historical six-hour and new four-hour limit sessions', async () => {
    const makeLimitSession = (
      sessionId: string,
      startedAt: string,
      completedAt: string,
      creditedSeconds: number,
      maxFocusSeconds: number,
    ): { history: HistoryItem; detail: FocusSessionDetail } => {
      const limitHistory: HistoryItem = {
        ...history,
        session_id: sessionId,
        started_at: startedAt,
        completed_at: completedAt,
        credited_focus_seconds: creditedSeconds,
        completion_reason: 'focus_limit',
      };
      return {
        history: limitHistory,
        detail: {
          ...detail,
          session: {
            ...detail.session,
            session_id: sessionId,
            started_at: startedAt,
            completed_at: completedAt,
            accumulated_focus_seconds: creditedSeconds,
            credited_focus_seconds: creditedSeconds,
            completion_reason: 'focus_limit',
            max_focus_seconds: maxFocusSeconds,
            task_history: [],
          },
          segments: [{ started_at: startedAt, ended_at: completedAt }],
          settlement: { reason: 'focus_limit', counts_toward_stats: true },
        },
      };
    };
    const oldSixHour = makeLimitSession(
      '00000000-0000-4000-8000-000000000010',
      '2026-08-03T00:00:00Z',
      '2026-08-03T06:00:00Z',
      21600,
      21600,
    );
    const newFourHour = makeLimitSession(
      '00000000-0000-4000-8000-000000000011',
      '2026-08-04T00:00:00Z',
      '2026-08-04T04:00:00Z',
      14400,
      14400,
    );
    const result = await buildFocusExport({
      period: 'weekly',
      summary: {
        ...summary,
        credited_focus_seconds: 36000,
        valid_session_count: 2,
        days: [
          {
            local_date: '2026-08-03',
            credited_focus_seconds: 21600,
            checkin_completed: true,
          },
          {
            local_date: '2026-08-04',
            credited_focus_seconds: 14400,
            checkin_completed: true,
          },
        ],
      },
      space: { id: detail.session.space_id, name: 'Research room' },
      memberId: history.member.member_id,
      sessions: [oldSixHour, newFourHour],
      exportedAt: '2026-08-10T00:00:01Z',
      dataUntil: '2026-08-10T00:00:01Z',
    });

    expect(result.content).toContain('schema_version: 1.1.0');
    expect(result.content).toContain('calculation_version: 1');
    expect(result.content).toContain('| effective_focus | 36000 | 10:00:00 |');
    expect(result.content).toContain('focus_limit\t2');
    expect(result.content).toContain('\t21600\t');
    expect(result.content).toContain('\t14400\t');
  });
});
