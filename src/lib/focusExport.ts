import type {
  FocusCategory,
  FocusSessionDetail,
  HistoryItem,
  StatsSummary,
} from '../domain/types';

export type ExportPeriod = 'weekly' | 'monthly';

export interface FocusExportSession {
  history: HistoryItem;
  detail: FocusSessionDetail;
}

export interface FocusExportInput {
  period: ExportPeriod;
  summary: StatsSummary;
  space: { id: string; name: string };
  memberId: string;
  sessions: FocusExportSession[];
  exportedAt: string;
  dataUntil: string;
}

const encoder = new TextEncoder();

async function sha256(value: string) {
  const bytes = await crypto.subtle.digest('SHA-256', encoder.encode(value));
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

const seconds = (value: string, epoch: number) =>
  Math.round((Date.parse(value) - epoch) / 1000);

function clip(
  startedAt: string,
  endedAt: string | null,
  rangeStart: number,
  rangeEnd: number,
) {
  const start = Math.max(Date.parse(startedAt), rangeStart);
  const end = Math.min(endedAt ? Date.parse(endedAt) : rangeEnd, rangeEnd);
  return end > start ? { start, end } : null;
}

function formatSeconds(value: number) {
  const safe = Math.max(0, Math.floor(value));
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  const remainder = safe % 60;
  return `${hours}:${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
}

function escapeTsv(value: string | number | boolean | null | undefined) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replaceAll('\\', '\\\\')
    .replaceAll('\t', '\\t')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n');
}

const row = (...values: Array<string | number | boolean | null | undefined>) =>
  values.map(escapeTsv).join('\t');

function taskStates(session: FocusExportSession) {
  const revisions = [...(session.detail.session.task_history ?? [])].sort(
    (left, right) => Date.parse(left.changed_at) - Date.parse(right.changed_at),
  );
  const states: Array<{
    at: string;
    task_name: string;
    category: FocusCategory;
  }> = [];
  if (revisions.length) {
    const first = revisions[0]!;
    states.push({
      at: session.history.started_at,
      task_name: first.task_name,
      category: first.category,
    });
    revisions.forEach((revision, index) => {
      const next = revisions[index + 1];
      states.push({
        at: revision.changed_at,
        task_name: next?.task_name ?? session.history.task_name,
        category: next?.category ?? session.history.category,
      });
    });
  } else {
    states.push({
      at: session.history.started_at,
      task_name: session.history.task_name,
      category: session.history.category,
    });
  }
  return states;
}

function localDate(value: number, timezone: string) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(value));
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function addIntervalByDay(
  totals: Map<string, number>,
  start: number,
  end: number,
  timezone: string,
) {
  let cursor = start;
  while (cursor < end) {
    const date = localDate(cursor, timezone);
    if (localDate(end - 1, timezone) === date) {
      totals.set(date, (totals.get(date) ?? 0) + (end - cursor) / 1000);
      break;
    }
    let low = cursor;
    let high = end;
    while (high - low > 1) {
      const middle = Math.floor((low + high) / 2);
      if (localDate(middle, timezone) === date) low = middle;
      else high = middle;
    }
    totals.set(date, (totals.get(date) ?? 0) + (high - cursor) / 1000);
    cursor = high;
  }
}

export async function buildFocusExport(input: FocusExportInput) {
  const rangeStart = Date.parse(input.summary.period_start);
  const rangeEnd = Date.parse(input.summary.period_end);
  const stable = async (kind: string, value: string) =>
    `${kind}_${(await sha256(`youjian-focus-export-v1:${kind}:${value}`)).slice(0, 16)}`;
  const subjectId = await stable('usr', input.memberId);
  const spaceId = await stable('spc', input.space.id);
  const sessionIds = new Map<string, string>();
  for (const session of input.sessions)
    sessionIds.set(
      session.history.session_id,
      await stable('ses', session.history.session_id),
    );

  const taskKey = (name: string, category: FocusCategory) =>
    `${category}\u0000${name}`;
  const taskIds = new Map<string, string>();
  for (const session of input.sessions) {
    for (const state of taskStates(session)) {
      const key = taskKey(state.task_name, state.category);
      if (!taskIds.has(key)) taskIds.set(key, await stable('tsk', key));
    }
  }

  const sessionRows: string[] = [];
  const changeRows: string[] = [];
  const invalidRows: string[] = [];
  const uncertainRows: string[] = [];
  const dailyElapsed = new Map<string, number>();
  const dailyActive = new Map<string, number>();
  const dailyInvalid = new Map<string, number>();
  const taskSeconds = new Map<string, number>();
  const termination = new Map<string, number>();

  for (const item of input.sessions) {
    const id = sessionIds.get(item.history.session_id)!;
    const baseline = taskStates(item);
    const initial = baseline[0]!;
    const initialTaskId = taskIds.get(
      taskKey(initial.task_name, initial.category),
    )!;
    const sessionSpan = clip(
      item.history.started_at,
      item.history.completed_at,
      rangeStart,
      rangeEnd,
    );
    if (!sessionSpan) continue;
    const reason = item.history.completion_reason;
    termination.set(reason, (termination.get(reason) ?? 0) + 1);
    addIntervalByDay(
      dailyElapsed,
      sessionSpan.start,
      sessionSpan.end,
      input.summary.timezone,
    );
    sessionRows.push(
      row(
        id,
        Math.round((sessionSpan.start - rangeStart) / 1000),
        Math.round((sessionSpan.end - rangeStart) / 1000),
        initialTaskId,
        spaceId,
        reason,
        item.history.counts_toward_stats ? 1 : 0,
      ),
    );

    baseline.slice(1).forEach((state, index) => {
      changeRows.push(
        row(
          id,
          seconds(state.at, rangeStart),
          index + 1,
          'T',
          taskIds.get(taskKey(state.task_name, state.category)),
        ),
      );
    });

    const segmentIntervals = item.detail.segments
      .map((segment) =>
        clip(segment.started_at, segment.ended_at, rangeStart, rangeEnd),
      )
      .filter((value): value is { start: number; end: number } =>
        Boolean(value),
      );
    for (const segment of segmentIntervals) {
      const target = item.history.counts_toward_stats
        ? dailyActive
        : dailyInvalid;
      addIntervalByDay(
        target,
        segment.start,
        segment.end,
        input.summary.timezone,
      );
      if (!item.history.counts_toward_stats) {
        invalidRows.push(
          row(
            id,
            Math.round((segment.start - rangeStart) / 1000),
            Math.round((segment.end - rangeStart) / 1000),
            'below_minimum_session',
          ),
        );
      } else {
        const boundaries = [
          segment.start,
          ...baseline
            .slice(1)
            .map((state) => Date.parse(state.at))
            .filter((at) => at > segment.start && at < segment.end),
          segment.end,
        ];
        for (let index = 0; index < boundaries.length - 1; index += 1) {
          const start = boundaries[index]!;
          const end = boundaries[index + 1]!;
          const state = [...baseline]
            .reverse()
            .find((candidate) => Date.parse(candidate.at) <= start)!;
          const key = taskIds.get(taskKey(state.task_name, state.category))!;
          taskSeconds.set(
            key,
            (taskSeconds.get(key) ?? 0) + (end - start) / 1000,
          );
        }
      }
    }

    item.detail.connection_unconfirmed_intervals.forEach((interval) => {
      const value = clip(
        interval.started_at,
        interval.ended_at,
        rangeStart,
        rangeEnd,
      );
      if (value)
        uncertainRows.push(
          row(
            id,
            Math.round((value.start - rangeStart) / 1000),
            Math.round((value.end - rangeStart) / 1000),
            'connection_unconfirmed',
          ),
        );
    });

    const events = [
      ...item.detail.segments.flatMap((segment) => [
        { at: segment.started_at, type: 'R' },
        ...(segment.ended_at ? [{ at: segment.ended_at, type: 'P' }] : []),
      ]),
    ]
      .filter(
        (event) =>
          Date.parse(event.at) > sessionSpan.start &&
          Date.parse(event.at) < sessionSpan.end,
      )
      .sort((left, right) => Date.parse(left.at) - Date.parse(right.at));
    events.forEach((event, index) =>
      changeRows.push(
        row(
          id,
          seconds(event.at, rangeStart),
          baseline.length + index,
          event.type,
        ),
      ),
    );
  }

  const activeTotal = [...dailyActive.values()].reduce((a, b) => a + b, 0);
  const elapsedTotal = [...dailyElapsed.values()].reduce((a, b) => a + b, 0);
  const invalidTotal = [...dailyInvalid.values()].reduce((a, b) => a + b, 0);
  const pausedTotal = Math.max(0, elapsedTotal - activeTotal - invalidTotal);
  if (Math.floor(activeTotal) !== input.summary.credited_focus_seconds) {
    throw new Error('FOCUS_EXPORT_INCONSISTENT_SNAPSHOT');
  }
  const currentLocalDate = localDate(
    Date.parse(input.dataUntil),
    input.summary.timezone,
  );
  const finalLocalDate = localDate(rangeEnd - 1, input.summary.timezone);
  const partial =
    currentLocalDate <= finalLocalDate &&
    Date.parse(input.dataUntil) < rangeEnd;

  const rawBlocks = [
    'sessions',
    row(
      'id',
      'start_s',
      'end_s',
      'task_id',
      'space_id',
      'end_reason',
      'credited',
    ),
    ...sessionRows.sort(),
    '',
    'changes',
    row('session_id', 'at_s', 'seq', 'type', 'value'),
    ...changeRows.sort(),
    '',
    'invalid_intervals',
    row('session_id', 'start_s', 'end_s', 'reason'),
    ...invalidRows.sort(),
    '',
    'unconfirmed_intervals',
    row('session_id', 'start_s', 'end_s', 'reason'),
    ...uncertainRows.sort(),
  ].join('\n');
  const eventsSha = await sha256(`${rawBlocks}\n`);
  const taskDictionary = [...taskIds.entries()]
    .map(([key, id]) => {
      const [category, name] = key.split('\u0000');
      return row(id, category, name);
    })
    .sort();
  const dailyRows = input.summary.days.map((day) => {
    const elapsed = Math.floor(dailyElapsed.get(day.local_date) ?? 0);
    const effective = Math.floor(dailyActive.get(day.local_date) ?? 0);
    const invalid = Math.floor(dailyInvalid.get(day.local_date) ?? 0);
    return row(
      day.local_date,
      effective,
      elapsed,
      Math.max(0, elapsed - effective - invalid),
      invalid,
    );
  });
  const periodLabel = input.period === 'weekly' ? 'Weekly' : 'Monthly';
  const content = `---\n+schema: youjian.focus-export\n+schema_version: 1.0.0\n+calculation_version: 1\n+exported_at: ${input.exportedAt}\n+timezone: ${input.summary.timezone}\n+period_type: ${input.period === 'weekly' ? 'week' : 'month'}\n+period_start: ${localDate(rangeStart, input.summary.timezone)}\n+period_end_exclusive: ${localDate(rangeEnd, input.summary.timezone)}\n+period_status: ${partial ? 'partial' : 'complete'}\n+data_until: ${input.dataUntil}\n+subject_id: ${subjectId}\n+record_count: ${sessionRows.length}\n+events_sha256: ${eventsSha}\n+---\n+\n+# Youjian Focus ${periodLabel} Report${partial ? ' (Partial)' : ''}\n+\n+## Period totals\n+\n+| metric | seconds | display |\n+| --- | ---: | ---: |\n+| effective_focus | ${Math.floor(activeTotal)} | ${formatSeconds(activeTotal)} |\n+| elapsed | ${Math.floor(elapsedTotal)} | ${formatSeconds(elapsedTotal)} |\n+| paused | ${Math.floor(pausedTotal)} | ${formatSeconds(pausedTotal)} |\n+| invalid | ${Math.floor(invalidTotal)} | ${formatSeconds(invalidTotal)} |\n+| sessions | ${sessionRows.length} | ${sessionRows.length} |\n+\n+## Daily totals (TSV)\n+\n+\`\`\`tsv\n+date\teffective_s\telapsed_s\tpaused_s\tinvalid_s\n+${dailyRows.join('\n')}\n+\`\`\`\n+\n+## Task allocation (TSV)\n+\n+\`\`\`tsv\n+task_id\teffective_s\n+${[
    ...taskSeconds.entries(),
  ]
    .sort()
    .map(([id, value]) => row(id, Math.floor(value)))
    .join(
      '\n',
    )}\n+\`\`\`\n+\n+## Space allocation (TSV)\n+\n+\`\`\`tsv\n+space_id\tname\teffective_s\n+${row(spaceId, input.space.name, Math.floor(activeTotal))}\n+\`\`\`\n+\n+## Termination reasons (TSV)\n+\n+\`\`\`tsv\n+reason\tsessions\n+${[
    ...termination.entries(),
  ]
    .sort()
    .map(([reason, count]) => row(reason, count))
    .join(
      '\n',
    )}\n+\`\`\`\n+\n+## Dictionaries (TSV)\n+\n+\`\`\`tsv\n+tasks\n+id\tcategory\tname\n+${taskDictionary.join('\n')}\n+\n+spaces\n+id\tname\n+${row(spaceId, input.space.name)}\n+\`\`\`\n+\n+## Raw timeline (TSV)\n+\n+Offsets are integer seconds from \`${input.summary.period_start}\`. Event codes: \`T=task change\`, \`P=pause\`, \`R=resume\`. TSV escapes are \`\\t\`, \`\\r\`, \`\\n\`, and \`\\\\\`. The SHA-256 digest covers the normalized UTF-8 raw block below plus one trailing LF.\n+\n+\`\`\`tsv\n+${rawBlocks}\n+\`\`\`\n+`;
  const periodStart = localDate(rangeStart, input.summary.timezone);
  const suffix = partial ? '_partial' : '';
  const filename =
    input.period === 'weekly'
      ? `youjian-focus-week-${periodStart}${suffix}.md`
      : `youjian-focus-month-${periodStart.slice(0, 7)}${suffix}.md`;
  return { content, filename, eventsSha256: eventsSha };
}

export function sessionOverlapsPeriod(
  detail: FocusSessionDetail,
  periodStart: string,
  periodEnd: string,
) {
  const start = Date.parse(periodStart);
  const end = Date.parse(periodEnd);
  return detail.segments.some((segment) =>
    Boolean(clip(segment.started_at, segment.ended_at, start, end)),
  );
}
