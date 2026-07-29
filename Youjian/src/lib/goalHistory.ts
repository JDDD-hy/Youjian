import type { GoalProposal, GoalType, PeriodType } from '../domain/types';
import { getSupabaseClient } from './supabase';
import { withRequestTimeout } from './api';
import { assertRouteSpace } from './spaceBoundary';

interface ProposalRow {
  id: string;
  space_id: string;
  proposer_member_id: string;
  goal_type: GoalType;
  period_type: PeriodType;
  target_value: number;
  status: 'rejected' | 'expired';
  created_at: string;
  expires_at: string;
  effective_period_start: string;
}

interface MemberRow {
  id: string;
  display_name: string;
}

export async function loadResolvedGoalProposals(spaceId: string) {
  const supabase = getSupabaseClient();
  const proposals = await withRequestTimeout(
    supabase
      .from('goal_proposals')
      .select(
        'id,space_id,proposer_member_id,goal_type,period_type,target_value,status,created_at,expires_at,effective_period_start',
      )
      .eq('space_id', spaceId)
      .in('status', ['rejected', 'expired'])
      .order('created_at', { ascending: false })
      .limit(30),
  );
  if (proposals.error) throw proposals.error;
  const rows = (proposals.data ?? []) as unknown as ProposalRow[];
  for (const row of rows)
    assertRouteSpace(spaceId, row.space_id, 'goal_history_space');
  const proposerIds = [...new Set(rows.map((row) => row.proposer_member_id))];
  const members = proposerIds.length
    ? await withRequestTimeout(
        supabase
          .from('space_members')
          .select('id,display_name')
          .in('id', proposerIds),
      )
    : { data: [] as MemberRow[], error: null };
  if (members.error) throw members.error;
  const names = new Map(
    ((members.data ?? []) as unknown as MemberRow[]).map((member) => [
      member.id,
      member.display_name,
    ]),
  );
  return rows.map((row): GoalProposal => ({
    proposal_id: row.id,
    proposer: {
      member_id: row.proposer_member_id,
      display_name: names.get(row.proposer_member_id) ?? '已停用成员',
    },
    goal_type: row.goal_type,
    period_type: row.period_type,
    target_value: row.target_value,
    status: row.status,
    created_at: row.created_at,
    expires_at: row.expires_at,
    effective_period_start: row.effective_period_start,
    required_vote_count: 0,
    accepted_vote_count: 0,
    my_vote: null,
  }));
}
