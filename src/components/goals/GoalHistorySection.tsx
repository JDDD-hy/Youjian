import type { Goal } from '../../domain/types';
import { GoalCard } from './GoalCard';
import { HistoryPanel } from './HistoryPanel';
export function GoalHistorySection(props: {
  spaceId: string;
  maintenanceVersion: number;
}) {
  return (
    <HistoryPanel<Goal> {...props} kind="goals" title="过往目标" pageSize={3}>
      {(items) =>
        items.map((goal) => <GoalCard key={goal.goal_id} goal={goal} />)
      }
    </HistoryPanel>
  );
}
