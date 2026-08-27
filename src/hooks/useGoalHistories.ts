import { useInfiniteQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import type { Goal, GoalProposal } from '../domain/types';
import { rpc } from '../lib/api';
import { assertRouteSpace } from '../lib/spaceBoundary';

const GOAL_HISTORY_PAGE_SIZE = 3;
const PROPOSAL_HISTORY_PAGE_SIZE = 4;

interface HistoryPage<T> {
  space_id: string;
  items: T[];
  next_cursor: string | null;
}

function useHistory<T>(
  queryKey: string,
  rpcName: string,
  spaceId: string,
  pageSize: number,
  maintenanceVersion: number,
) {
  const history = useInfiniteQuery({
    queryKey: [queryKey, spaceId],
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      const result = await rpc<HistoryPage<T>>(rpcName, {
        space_id: spaceId,
        limit: pageSize,
        cursor: pageParam,
      });
      assertRouteSpace(spaceId, result.data.space_id, `${queryKey}_space`);
      return result;
    },
    getNextPageParam: (last) => last.data.next_cursor ?? undefined,
  });
  const previousMaintenanceVersion = useRef(maintenanceVersion);
  const refetch = history.refetch;
  useEffect(() => {
    if (previousMaintenanceVersion.current === maintenanceVersion) return;
    previousMaintenanceVersion.current = maintenanceVersion;
    void refetch();
  }, [maintenanceVersion, refetch]);
  return history;
}

export function useGoalHistory(spaceId: string, maintenanceVersion: number) {
  return useHistory<Goal>(
    'goal-history',
    'list_goal_history',
    spaceId,
    GOAL_HISTORY_PAGE_SIZE,
    maintenanceVersion,
  );
}

export function useGoalProposalHistory(
  spaceId: string,
  maintenanceVersion: number,
) {
  return useHistory<GoalProposal>(
    'goal-proposal-history',
    'list_goal_proposal_history',
    spaceId,
    PROPOSAL_HISTORY_PAGE_SIZE,
    maintenanceVersion,
  );
}
