import { ErrorState } from '../AsyncState';
import { useGoalProposalHistory } from '../../hooks/useGoalHistories';
import { proposalSentence } from '../../lib/goalPreview';

export function ProposalHistorySection({
  spaceId,
  maintenanceVersion,
}: {
  spaceId: string;
  maintenanceVersion: number;
}) {
  const history = useGoalProposalHistory(spaceId, maintenanceVersion);
  const items = history.data?.pages.flatMap((page) => page.data.items) ?? [];

  if (history.isLoading || (!items.length && !history.error)) return null;

  return (
    <section className="section">
      <div className="section-heading">
        <h2>已结束提案</h2>
      </div>
      {history.error && items.length === 0 ? (
        <ErrorState
          title="无法加载已结束提案"
          message="被拒绝和已过期的提案尚未完整加载。"
          onRetry={() => void history.refetch()}
        />
      ) : (
        <>
          {history.error && (
            <div className="inline-notice inline-notice--warning" role="status">
              更多已结束提案暂时没有加载，当前记录仍可查看。
            </div>
          )}
          <div className="proposal-list">
            {items.map((proposal) => (
              <article className="proposal-card" key={proposal.proposal_id}>
                <span className="pill">
                  {proposal.status === 'rejected' ? '已拒绝' : '已过期'}
                </span>
                <h3>
                  {proposalSentence(
                    proposal.goal_type,
                    proposal.period_type,
                    proposal.target_value,
                  )}
                </h3>
                <small>发起人：{proposal.proposer.display_name}</small>
              </article>
            ))}
          </div>
          {history.hasNextPage && (
            <button
              className="button button--secondary button--full"
              disabled={history.isFetchingNextPage}
              onClick={() => void history.fetchNextPage()}
            >
              {history.isFetchingNextPage ? '正在加载…' : '加载更多提案'}
            </button>
          )}
        </>
      )}
    </section>
  );
}
