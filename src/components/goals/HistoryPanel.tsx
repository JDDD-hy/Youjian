import { parseHistoryPage } from '../../lib/historyPage';
import { useQuery } from '@tanstack/react-query';
import { useId, useState, type ReactNode } from 'react';
import { rpc } from '../../lib/api';
import { assertRouteSpace } from '../../lib/spaceBoundary';
import { AccessibleModal } from '../AccessibleModal';
import { ErrorState, PageLoader } from '../AsyncState';
import { Presence } from '../Presence';

function PageJump({
  page,
  max,
  disabled,
  onJump,
}: {
  page: number;
  max: number;
  disabled: boolean;
  onJump: (page: number) => void;
}) {
  const [input, setInput] = useState(String(page));
  const [invalid, setInvalid] = useState(false);
  const errorId = useId();
  const jump = () => {
    const next = parseHistoryPage(input, max);
    setInvalid(next === null);
    if (next !== null) {
      setInput(String(next));
      onJump(next);
    }
  };
  return (
    <div className="history-page-jump">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          jump();
        }}
      >
        <input
          aria-label="跳转页码"
          aria-invalid={invalid}
          aria-describedby={invalid ? errorId : undefined}
          inputMode="numeric"
          autoComplete="off"
          value={input}
          disabled={disabled}
          onChange={(event) => setInput(event.target.value)}
          onBlur={jump}
          onKeyDown={(event) => {
            if (event.key === 'Escape') {
              event.preventDefault();
              event.stopPropagation();
              setInput(String(page));
              setInvalid(false);
            }
          }}
        />
        <span>/ {max}</span>
      </form>
      {invalid && (
        <span id={errorId} className="history-page-error" role="alert">
          请输入 1–{max} 之间的整数页码
        </span>
      )}
    </div>
  );
}

export function HistoryPanel<T>({
  spaceId,
  maintenanceVersion,
  kind,
  title,
  pageSize,
  children,
}: {
  spaceId: string;
  maintenanceVersion: number;
  kind: 'goals' | 'proposals';
  title: string;
  pageSize: number;
  children: (items: T[]) => ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [page, setPage] = useState(1);
  const titleId = useId();
  const history = useQuery({
    queryKey: [
      'goal-numbered-history',
      spaceId,
      kind,
      page,
      maintenanceVersion,
    ],
    enabled: open,
    placeholderData: (previous) =>
      previous?.space_id === spaceId ? previous : undefined,
    queryFn: async () => {
      const result = await rpc<{
        space_id: string;
        items: T[];
        page: number;
        page_count: number;
        total_count: number;
      }>('list_goal_history_page', {
        space_id: spaceId,
        kind,
        page,
        limit: pageSize,
      });
      assertRouteSpace(
        spaceId,
        result.data.space_id,
        'goal_history_page_space',
      );
      return result.data;
    },
  });
  const data = history.data;
  return (
    <>
      <button
        className="button button--text history-panel-trigger"
        onClick={() => setOpen(true)}
      >
        {title} ›
      </button>
      <Presence>
        {open && (
          <AccessibleModal titleId={titleId} onClose={() => setOpen(false)}>
            <div className="goal-history-panel">
              <div className="section-heading">
                <h2 id={titleId}>{title}</h2>
                <button
                  className="button button--text"
                  aria-label={`关闭${title}`}
                  onClick={() => setOpen(false)}
                >
                  关闭
                </button>
              </div>
              {history.isPending ? (
                <PageLoader />
              ) : history.error ? (
                <ErrorState
                  title={`无法加载${title}`}
                  onRetry={() => void history.refetch()}
                />
              ) : (
                data && (
                  <>
                    <div
                      className="goal-history-panel__items"
                      aria-busy={history.isFetching}
                    >
                      {data.items.length ? (
                        children(data.items)
                      ) : (
                        <p className="quiet-copy">暂无{title}。</p>
                      )}
                    </div>
                    <div className="history-pager">
                      <button
                        className="button button--text"
                        disabled={history.isFetching || data.page <= 1}
                        onClick={() => setPage(data.page - 1)}
                      >
                        ‹ 上一页
                      </button>
                      <PageJump
                        key={data.page}
                        page={data.page}
                        max={data.page_count}
                        disabled={history.isFetching}
                        onJump={setPage}
                      />
                      <button
                        className="button button--text"
                        disabled={
                          history.isFetching || data.page >= data.page_count
                        }
                        onClick={() => setPage(data.page + 1)}
                      >
                        下一页 ›
                      </button>
                    </div>
                    <p className="history-panel-count" role="status">
                      共 {data.total_count} 条 · 第 {data.page} /{' '}
                      {data.page_count} 页
                      {history.isFetching ? ' · 正在加载…' : ''}
                    </p>
                  </>
                )
              )}
            </div>
          </AccessibleModal>
        )}
      </Presence>
    </>
  );
}
