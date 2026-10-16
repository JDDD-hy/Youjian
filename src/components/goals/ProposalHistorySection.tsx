import type { GoalProposal } from '../../domain/types';
import { proposalSentence } from '../../lib/goalPreview';
import { HistoryPanel } from './HistoryPanel';
export function ProposalHistorySection(props: {
  spaceId: string;
  maintenanceVersion: number;
}) {
  return (
    <HistoryPanel<GoalProposal>
      {...props}
      kind="proposals"
      title="已结束提案"
      pageSize={4}
    >
      {(items) =>
        items.map((proposal) => (
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
        ))
      }
    </HistoryPanel>
  );
}
