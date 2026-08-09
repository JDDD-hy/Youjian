import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { useParams } from 'react-router-dom';
import type {
  FocusSessionDetail,
  HistoryItem,
  HomeSnapshot,
  StatsSummary,
} from '../domain/types';
import { rpc } from '../lib/api';
import {
  categoryLabels,
  completionLabels,
  formatDuration,
  formatLocalDateTime,
  isoDateInTimezone,
  splitSegmentsByLocalDate,
} from '../lib/format';
import { AccessibleModal } from '../components/AccessibleModal';
import { Icon } from '../components/Icons';
import { EmptyState, ErrorState, PageLoader } from '../components/AsyncState';
import { assertRouteSpace } from '../lib/spaceBoundary';
import { StatsDistribution } from '../components/StatsDistribution';
import {
  STATS_QUERY_RETRY_COUNT,
  statsQueryRetryDelay,
} from '../lib/statsRetry';
import {
  buildFocusExport,
  sessionOverlapsPeriod,
  type ExportPeriod,
  type FocusExportSession,
} from '../lib/focusExport';

type View = 'mine' | 'space';
type Period = 'daily' | 'weekly' | 'monthly';

function isoWeekValue(localDate: string) {
  const date = new Date(`${localDate}T00:00:00Z`);
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil(
    ((date.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7,
  );
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

function weekMonday(value: string) {
  const match = /^(\d{4})-W(\d{2})$/.exec(value);
  if (!match) return '';
  const year = Number(match[1]);
  const week = Number(match[2]);
  const januaryFourth = new Date(Date.UTC(year, 0, 4));
  const monday = new Date(januaryFourth);
  monday.setUTCDate(
    januaryFourth.getUTCDate() -
      (januaryFourth.getUTCDay() || 7) +
      1 +
      (week - 1) * 7,
  );
  return monday.toISOString().slice(0, 10);
}

function shortDate(date: Date) {
  return `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
}

function exportPeriodLabel(period: ExportPeriod, value: string) {
  if (period === 'weekly') {
    const mondayValue = weekMonday(value);
    if (!mondayValue) return '选择一周';
    const monday = new Date(`${mondayValue}T00:00:00Z`);
    const sunday = new Date(monday);
    sunday.setUTCDate(monday.getUTCDate() + 6);
    return `${shortDate(monday)} ~ ${shortDate(sunday)}`;
  }
  const match = /^(\d{4})-(\d{2})$/.exec(value);
  return match ? `${match[1]}年${Number(match[2])}月` : '选择一个月';
}

function downloadText(filename: string, content: string) {
  const url = URL.createObjectURL(
    new Blob([content], { type: 'text/markdown;charset=utf-8' }),
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

export function StatsPage() {
  const { spaceId = '' } = useParams();
  const [view, setView] = useState<View>('mine');
  const [period, setPeriod] = useState<Period>('weekly');
  const [detail, setDetail] = useState<HistoryItem | null>(null);
  const [exportOpen, setExportOpen] = useState(false);
  const [exportPeriod, setExportPeriod] = useState<ExportPeriod>('weekly');
  const [exportSelection, setExportSelection] = useState('');
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState('');
  const home = useQuery({
    queryKey: ['home', spaceId],
    queryFn: async () => {
      const value = await rpc<HomeSnapshot>('get_home_snapshot', {
        space_id: spaceId,
      });
      assertRouteSpace(spaceId, value.data.space.id, 'stats_home_space');
      return {
        snapshot: value.data,
        serverNow: value.serverNow,
        receivedAt: Date.now(),
      };
    },
  });
  const timezone = home.data
    ? view === 'mine'
      ? home.data.snapshot.me.profile_timezone
      : home.data.snapshot.space.timezone
    : undefined;
  const anchor = timezone ? isoDateInTimezone(timezone) : undefined;
  const currentExportSelection = anchor
    ? exportPeriod === 'weekly'
      ? isoWeekValue(anchor)
      : anchor.slice(0, 7)
    : '';
  const summary = useQuery({
    queryKey: ['stats', spaceId, view, period, anchor],
    enabled: Boolean(anchor),
    retry: STATS_QUERY_RETRY_COUNT,
    retryDelay: statsQueryRetryDelay,
    queryFn: async () => {
      const result = await rpc<StatsSummary>('get_stats_summary', {
        space_id: spaceId,
        view,
        period,
        anchor_local_date: anchor,
      });
      assertRouteSpace(spaceId, result.data.space_id, 'stats_summary_space');
      return result;
    },
  });
  const range = summary.data?.data;
  const history = useInfiniteQuery({
    queryKey: [
      'history',
      spaceId,
      view,
      range?.period_start,
      range?.period_end,
    ],
    enabled: Boolean(range),
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      const result = await rpc<{
        space_id: string;
        items: HistoryItem[];
        next_cursor: string | null;
      }>('list_focus_history', {
        space_id: spaceId,
        view,
        period_start: range!.period_start,
        period_end: range!.period_end,
        limit: 30,
        cursor: pageParam,
      });
      assertRouteSpace(spaceId, result.data.space_id, 'focus_history_space');
      return result;
    },
    getNextPageParam: (last) => last.data.next_cursor ?? undefined,
  });
  const items = history.data?.pages.flatMap((page) => page.data.items) ?? [];
  const sessionDetail = useQuery({
    queryKey: ['focus-session-detail', detail?.session_id],
    enabled: Boolean(detail),
    retry: false,
    queryFn: async () => {
      const result = await rpc<FocusSessionDetail>('get_focus_session_detail', {
        session_id: detail!.session_id,
      });
      assertRouteSpace(
        spaceId,
        result.data.session.space_id,
        'focus_detail_space',
      );
      return result;
    },
  });
  const openExport = () => {
    setExportSelection(currentExportSelection);
    setExportError('');
    setExportOpen(true);
  };
  const runExport = async () => {
    if (!home.data || !exportSelection) return;
    setExporting(true);
    setExportError('');
    try {
      const anchorLocalDate =
        exportPeriod === 'weekly'
          ? weekMonday(exportSelection)
          : `${exportSelection}-01`;
      const exportSummary = await rpc<StatsSummary>('get_stats_summary', {
        space_id: spaceId,
        view: 'mine',
        period: exportPeriod,
        anchor_local_date: anchorLocalDate,
      });
      assertRouteSpace(
        spaceId,
        exportSummary.data.space_id,
        'focus_export_summary_space',
      );
      const expandedStart = new Date(
        Date.parse(exportSummary.data.period_start) - 7 * 60 * 60 * 1000,
      ).toISOString();
      const expandedEnd = new Date(
        Date.parse(exportSummary.data.period_end) + 7 * 60 * 60 * 1000,
      ).toISOString();
      const historyItems: HistoryItem[] = [];
      let cursor: string | null = null;
      do {
        const page: {
          data: {
            space_id: string;
            items: HistoryItem[];
            next_cursor: string | null;
          };
          serverNow: string;
          requestId: string;
        } = await rpc<{
          space_id: string;
          items: HistoryItem[];
          next_cursor: string | null;
        }>('list_focus_history', {
          space_id: spaceId,
          view: 'mine',
          period_start: expandedStart,
          period_end: expandedEnd,
          limit: 100,
          cursor,
        });
        assertRouteSpace(
          spaceId,
          page.data.space_id,
          'focus_export_history_space',
        );
        historyItems.push(...page.data.items);
        cursor = page.data.next_cursor;
      } while (cursor);
      const sessions: FocusExportSession[] = [];
      for (let index = 0; index < historyItems.length; index += 6) {
        const batch = await Promise.all(
          historyItems.slice(index, index + 6).map(async (historyItem) => {
            const response = await rpc<FocusSessionDetail>(
              'get_focus_session_detail',
              { session_id: historyItem.session_id },
            );
            assertRouteSpace(
              spaceId,
              response.data.session.space_id,
              'focus_export_detail_space',
            );
            return { history: historyItem, detail: response.data };
          }),
        );
        sessions.push(...batch);
      }
      const overlapping = sessions.filter(({ detail: session }) =>
        sessionOverlapsPeriod(
          session,
          exportSummary.data.period_start,
          exportSummary.data.period_end,
        ),
      );
      const result = await buildFocusExport({
        period: exportPeriod,
        summary: exportSummary.data,
        space: {
          id: home.data.snapshot.space.id,
          name: home.data.snapshot.space.name,
        },
        memberId: home.data.snapshot.me.member_id,
        sessions: overlapping,
        exportedAt: exportSummary.serverNow,
        dataUntil: exportSummary.serverNow,
      });
      downloadText(result.filename, result.content);
      setExportOpen(false);
    } catch (error) {
      setExportError(
        error instanceof Error &&
          error.message === 'FOCUS_EXPORT_INCONSISTENT_SNAPSHOT'
          ? '统计数据刚刚发生变化，请重新导出。'
          : '导出失败，未生成文件。请稍后重试。',
      );
    } finally {
      setExporting(false);
    }
  };
  return (
    <div className="page stats-page">
      <header className="page-header">
        <div>
          <p className="eyebrow">回看自己的节奏</p>
          <h1>统计</h1>
        </div>
      </header>
      <div className="segmented" aria-label="统计视角">
        {(
          [
            ['mine', '我的'],
            ['space', '友间'],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            className={view === value ? 'active' : ''}
            aria-pressed={view === value}
            onClick={() => setView(value)}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="segmented segmented--small" aria-label="统计周期">
        {(
          [
            ['daily', '日'],
            ['weekly', '周'],
            ['monthly', '月'],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            className={period === value ? 'active' : ''}
            aria-pressed={period === value}
            onClick={() => setPeriod(value)}
          >
            {label}
          </button>
        ))}
      </div>
      {home.isLoading || summary.isLoading ? (
        <PageLoader />
      ) : !home.data || !range ? (
        <ErrorState
          onRetry={() => {
            void home.refetch();
            void summary.refetch();
          }}
        />
      ) : (
        <>
          {(home.error || summary.error) && (
            <div className="inline-notice inline-notice--warning" role="status">
              部分统计暂时没有更新，正在显示上次成功加载的数据。
              <button
                type="button"
                onClick={() => {
                  void home.refetch();
                  void summary.refetch();
                }}
              >
                重新加载
              </button>
            </div>
          )}
          <section className="metric-grid">
            <article>
              <small>专注时间</small>
              <strong>{formatDuration(range.credited_focus_seconds)}</strong>
            </article>
            <article>
              <small>有效专注</small>
              <strong>{range.valid_session_count} 次</strong>
            </article>
            <article>
              <small>打卡天数</small>
              <strong>{range.checkin_day_count} 天</strong>
            </article>
          </section>
          <section className="chart-card" aria-labelledby="trend-title">
            <StatsDistribution summary={range} />
          </section>
          <section className="section">
            <div className="section-heading">
              <h2>历史记录</h2>
              <button
                type="button"
                className="button button--text stats-export-trigger"
                onClick={openExport}
              >
                数据导出
              </button>
            </div>
            {history.error && items.length > 0 && (
              <div
                className="inline-notice inline-notice--warning"
                role="status"
              >
                新的历史记录暂时没有加载，当前列表仍可查看。
              </div>
            )}
            {history.isLoading ? (
              <PageLoader />
            ) : items.length ? (
              <>
                <div className="history-list">
                  {items.map((item) => (
                    <button
                      className="history-row"
                      key={item.session_id}
                      onClick={() => setDetail(item)}
                    >
                      <span className="history-row__date">
                        {formatLocalDateTime(item.started_at, range.timezone)}
                      </span>
                      <span className="history-row__main">
                        <strong>{item.task_name}</strong>
                        <small>
                          {view === 'space'
                            ? `${item.member.display_name} · `
                            : ''}
                          {categoryLabels[item.category]}
                          {item.unconfirmed_connection_seconds > 0
                            ? ' · 含连接不可确认区间'
                            : ''}
                        </small>
                      </span>
                      <span className={item.counts_toward_stats ? '' : 'muted'}>
                        {formatDuration(item.credited_focus_seconds)}
                      </span>
                    </button>
                  ))}
                </div>
                {history.hasNextPage && (
                  <button
                    className="button button--secondary button--full"
                    disabled={history.isFetchingNextPage}
                    onClick={() => void history.fetchNextPage()}
                  >
                    {history.isFetchingNextPage ? '正在加载…' : '加载更多'}
                  </button>
                )}
              </>
            ) : history.error ? (
              <ErrorState
                title="无法加载历史记录"
                message="专注记录尚未完整加载。"
                onRetry={() => void history.refetch()}
              />
            ) : (
              <EmptyState icon="clock" title="还没有专注记录">
                <p>从点亮第一盏灯开始。</p>
              </EmptyState>
            )}
          </section>
        </>
      )}
      {detail && (
        <AccessibleModal titleId="detail-title" onClose={() => setDetail(null)}>
          <span className="drawer__handle" />
          <p className="eyebrow">专注记录</p>
          <h2 id="detail-title">{detail.task_name}</h2>
          <dl className="detail-list">
            <div>
              <dt>成员</dt>
              <dd>{detail.member.display_name}</dd>
            </div>
            <div>
              <dt>分类</dt>
              <dd>{categoryLabels[detail.category]}</dd>
            </div>
            <div>
              <dt>实际专注</dt>
              <dd>{formatDuration(detail.credited_focus_seconds)}</dd>
            </div>
            <div>
              <dt>开始</dt>
              <dd>{formatLocalDateTime(detail.started_at, range?.timezone)}</dd>
            </div>
            <div>
              <dt>结束</dt>
              <dd>
                {formatLocalDateTime(detail.completed_at, range?.timezone)}
              </dd>
            </div>
            <div>
              <dt>结算</dt>
              <dd>{completionLabels[detail.completion_reason]}</dd>
            </div>
            {!detail.counts_toward_stats && (
              <div>
                <dt>统计</dt>
                <dd>少于 5 分钟，不计入统计</dd>
              </div>
            )}
            {detail.unconfirmed_connection_seconds > 0 && (
              <div>
                <dt>连接</dt>
                <dd>
                  约 {formatDuration(detail.unconfirmed_connection_seconds)}
                  不可确认
                </dd>
              </div>
            )}
          </dl>
          {sessionDetail.error && sessionDetail.data && (
            <div className="inline-notice inline-notice--warning" role="status">
              记录详情暂时没有更新，当前内容仍可查看。
              <button
                type="button"
                onClick={() => void sessionDetail.refetch()}
              >
                重新加载
              </button>
            </div>
          )}
          {sessionDetail.isLoading ? (
            <PageLoader />
          ) : sessionDetail.data ? (
            <>
              <section aria-labelledby="segments-title">
                <h3 id="segments-title">专注分段</h3>
                {sessionDetail.data.data.segments.length ? (
                  <ol className="detail-timeline">
                    {sessionDetail.data.data.segments.map((segment, index) => (
                      <li key={`${segment.started_at}:${index}`}>
                        {formatLocalDateTime(
                          segment.started_at,
                          range?.timezone,
                        )}
                        {' — '}
                        {segment.ended_at
                          ? formatLocalDateTime(
                              segment.ended_at,
                              range?.timezone,
                            )
                          : '尚未结束'}
                      </li>
                    ))}
                  </ol>
                ) : (
                  <p className="quiet-copy">没有可显示的专注分段。</p>
                )}
              </section>
              <section aria-labelledby="date-attribution-title">
                <h3 id="date-attribution-title">按日期归属</h3>
                {range?.timezone ? (
                  <dl className="detail-list">
                    {splitSegmentsByLocalDate(
                      sessionDetail.data.data.segments,
                      range.timezone,
                    ).map((item) => (
                      <div key={item.local_date}>
                        <dt>{item.local_date}</dt>
                        <dd>{formatDuration(item.credited_focus_seconds)}</dd>
                      </div>
                    ))}
                  </dl>
                ) : (
                  <p className="quiet-copy">统计时区尚未确认。</p>
                )}
              </section>
              <section aria-labelledby="connection-title">
                <h3 id="connection-title">连接不可确认区间</h3>
                {sessionDetail.data.data.connection_unconfirmed_intervals
                  .length ? (
                  <ol className="detail-timeline">
                    {sessionDetail.data.data.connection_unconfirmed_intervals.map(
                      (interval, index) => (
                        <li key={`${interval.started_at}:${index}`}>
                          {formatLocalDateTime(
                            interval.started_at,
                            range?.timezone,
                          )}
                          {' — '}
                          {interval.ended_at
                            ? formatLocalDateTime(
                                interval.ended_at,
                                range?.timezone,
                              )
                            : '尚未确认'}
                        </li>
                      ),
                    )}
                  </ol>
                ) : (
                  <p className="quiet-copy">本次记录没有连接不可确认区间。</p>
                )}
              </section>
            </>
          ) : sessionDetail.error ? (
            <ErrorState
              title="无法加载记录详情"
              message="分段与连接区间尚未加载。"
              onRetry={() => void sessionDetail.refetch()}
            />
          ) : null}
          <button
            data-autofocus
            className="button button--secondary button--full"
            onClick={() => setDetail(null)}
          >
            关闭
          </button>
        </AccessibleModal>
      )}
      {exportOpen && (
        <AccessibleModal
          titleId="focus-export-title"
          onClose={() => !exporting && setExportOpen(false)}
        >
          <span className="drawer__handle" />
          <p className="eyebrow">专注数据</p>
          <h2 id="focus-export-title">数据导出</h2>
          <div
            className="segmented stats-export-period-tabs"
            aria-label="导出周期"
          >
            {(
              [
                ['weekly', '周'],
                ['monthly', '月'],
              ] as const
            ).map(([value, label]) => (
              <button
                key={value}
                type="button"
                className={exportPeriod === value ? 'active' : ''}
                aria-pressed={exportPeriod === value}
                disabled={exporting}
                onClick={() => {
                  setExportPeriod(value);
                  if (anchor)
                    setExportSelection(
                      value === 'weekly'
                        ? isoWeekValue(anchor)
                        : anchor.slice(0, 7),
                    );
                }}
              >
                {label}
              </button>
            ))}
          </div>
          <div className="stats-export-picker-group">
            <span className="stats-export-picker-label">
              {exportPeriod === 'weekly' ? '选择周' : '选择月'}
            </span>
            <label className="stats-export-picker">
              <span className="stats-export-picker__date">
                {exportPeriodLabel(exportPeriod, exportSelection)}
              </span>
              <span className="stats-export-picker__icon">
                <Icon name="calendar" width={20} height={20} />
              </span>
              <input
                data-autofocus
                className="stats-export-picker__input"
                aria-label={exportPeriod === 'weekly' ? '选择周' : '选择月'}
                type={exportPeriod === 'weekly' ? 'week' : 'month'}
                value={exportSelection}
                max={currentExportSelection}
                disabled={exporting}
                onChange={(event) => setExportSelection(event.target.value)}
              />
            </label>
          </div>
          <p className="quiet-copy stats-export-note">
            仅导出你本人在当前友间的数据。文件内容使用英语，空周期也可导出。
          </p>
          {exportError && (
            <div className="inline-notice inline-notice--warning" role="alert">
              {exportError}
            </div>
          )}
          <div className="stats-export-actions">
            <button
              type="button"
              className="button button--secondary"
              disabled={exporting}
              onClick={() => setExportOpen(false)}
            >
              取消
            </button>
            <button
              type="button"
              className="button button--primary"
              disabled={exporting || !exportSelection}
              onClick={() => void runExport()}
            >
              {exporting ? '正在导出…' : '导出 Markdown'}
            </button>
          </div>
        </AccessibleModal>
      )}
    </div>
  );
}
