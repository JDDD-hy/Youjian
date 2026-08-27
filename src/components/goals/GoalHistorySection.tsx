import { ErrorState } from '../AsyncState';
import { GoalCard } from './GoalCard';
import { useGoalHistory } from '../../hooks/useGoalHistories';

export function GoalHistorySection({
  spaceId,
  maintenanceVersion,
}: {
  spaceId: string;
  maintenanceVersion: number;
}) {
  const history = useGoalHistory(spaceId, maintenanceVersion);
  const items = history.data?.pages.flatMap((page) => page.data.items) ?? [];

  if (history.isLoading || (!items.length && !history.error)) return null;

  return (
    <section className="section">
      <div className="section-heading">
        <h2>过往目标</h2>
      </div>
      {history.error && items.length === 0 ? (
        <ErrorState
          title="无法加载过往目标"
          message="过往目标尚未完整加载。"
          onRetry={() => void history.refetch()}
        />
      ) : (
        <>
          {history.error && (
            <div className="inline-notice inline-notice--warning" role="status">
              更多过往目标暂时没有加载，当前记录仍可查看。
            </div>
          )}
          {items.map((goal) => (
            <GoalCard key={goal.goal_id} goal={goal} />
          ))}
          {history.hasNextPage && (
            <button
              className="button button--secondary button--full"
              disabled={history.isFetchingNextPage}
              onClick={() => void history.fetchNextPage()}
            >
              {history.isFetchingNextPage ? '正在加载…' : '加载更多目标'}
            </button>
          )}
        </>
      )}
    </section>
  );
}
