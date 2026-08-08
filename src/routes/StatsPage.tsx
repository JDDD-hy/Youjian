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
import { EmptyState, ErrorState, PageLoader } from '../components/AsyncState';
import { assertRouteSpace } from '../lib/spaceBoundary';
import { StatsDistribution } from '../components/StatsDistribution';

type View = 'mine' | 'space';
type Period = 'daily' | 'weekly' | 'monthly';

export function StatsPage() {
  const { spaceId = '' } = useParams();
  const [view, setView] = useState<View>('mine');
  const [period, setPeriod] = useState<Period>('weekly');
  const [detail, setDetail] = useState<HistoryItem | null>(null);
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
  const summary = useQuery({
    queryKey: ['stats', spaceId, view, period, anchor],
    enabled: Boolean(anchor),
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
              <span>不可修改</span>
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
    </div>
  );
}
