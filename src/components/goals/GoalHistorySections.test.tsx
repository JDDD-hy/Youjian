import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Goal, GoalProposal } from '../../domain/types';
import { GoalHistorySection } from './GoalHistorySection';
import { ProposalHistorySection } from './ProposalHistorySection';

const rpc = vi.hoisted(() => vi.fn());
vi.mock('../../lib/api', () => ({ rpc }));

function goal(index: number): Goal {
  return {
    goal_id: `goal-${index}`,
    goal_type: 'group_total_minutes',
    period_type: 'weekly',
    target_value: index,
    status: 'completed',
    starts_at: `2026-08-${String(20 - index).padStart(2, '0')}T00:00:00Z`,
    ends_at: `2026-08-${String(21 - index).padStart(2, '0')}T00:00:00Z`,
    progress: { credited_value: index, completed: true, members: null },
  };
}

function proposal(index: number): GoalProposal {
  return {
    proposal_id: `proposal-${index}`,
    proposer: { member_id: 'member', display_name: `成员 ${index}` },
    goal_type: 'group_total_minutes',
    period_type: 'weekly',
    target_value: index,
    status: index % 2 ? 'rejected' : 'expired',
    created_at: `2026-08-${String(20 - index).padStart(2, '0')}T00:00:00Z`,
    expires_at: `2026-08-${String(21 - index).padStart(2, '0')}T00:00:00Z`,
    effective_period_start: '2026-09-01T00:00:00Z',
    required_vote_count: 2,
    accepted_vote_count: 1,
    my_vote: null,
  };
}

function sections(client: QueryClient, maintenanceVersion: number) {
  return (
    <QueryClientProvider client={client}>
      <GoalHistorySection
        spaceId="space"
        maintenanceVersion={maintenanceVersion}
      />
      <ProposalHistorySection
        spaceId="space"
        maintenanceVersion={maintenanceVersion}
      />
    </QueryClientProvider>
  );
}

function mount() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return { client, view: render(sections(client, 1)) };
}

describe('goal history sections', () => {
  beforeEach(() => {
    rpc.mockReset();
    rpc.mockImplementation(
      (name: string, params: { cursor: string | null }) => {
        if (name === 'list_goal_history')
          return Promise.resolve({
            data: {
              space_id: 'space',
              items: params.cursor
                ? [goal(4), goal(5)]
                : [goal(1), goal(2), goal(3)],
              next_cursor: params.cursor ? null : 'goal-next',
            },
          });
        if (name === 'list_goal_proposal_history')
          return Promise.resolve({
            data: {
              space_id: 'space',
              items: params.cursor
                ? [proposal(5)]
                : [proposal(1), proposal(2), proposal(3), proposal(4)],
              next_cursor: params.cursor ? null : 'proposal-next',
            },
          });
        throw new Error(`Unexpected RPC ${name}`);
      },
    );
  });

  it('loads three goals and four proposals per cursor page', async () => {
    const { view } = mount();

    await screen.findByRole('button', { name: '加载更多目标' });
    expect(view.container.querySelectorAll('.goal-card')).toHaveLength(3);
    expect(view.container.querySelectorAll('.proposal-card')).toHaveLength(4);
    expect(rpc).toHaveBeenCalledWith('list_goal_history', {
      space_id: 'space',
      limit: 3,
      cursor: null,
    });
    expect(rpc).toHaveBeenCalledWith('list_goal_proposal_history', {
      space_id: 'space',
      limit: 4,
      cursor: null,
    });

    fireEvent.click(screen.getByRole('button', { name: '加载更多目标' }));
    fireEvent.click(screen.getByRole('button', { name: '加载更多提案' }));

    await waitFor(() => {
      expect(view.container.querySelectorAll('.goal-card')).toHaveLength(5);
      expect(view.container.querySelectorAll('.proposal-card')).toHaveLength(5);
    });
    expect(rpc).toHaveBeenCalledWith('list_goal_history', {
      space_id: 'space',
      limit: 3,
      cursor: 'goal-next',
    });
    expect(rpc).toHaveBeenCalledWith('list_goal_proposal_history', {
      space_id: 'space',
      limit: 4,
      cursor: 'proposal-next',
    });
    expect(
      screen.queryByRole('button', { name: '加载更多目标' }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: '加载更多提案' }),
    ).not.toBeInTheDocument();
  });

  it('refetches histories only after the maintained snapshot version changes', async () => {
    const { client, view } = mount();
    await screen.findByRole('button', { name: '加载更多目标' });
    expect(
      rpc.mock.calls.filter(([name]) => name === 'list_goal_history'),
    ).toHaveLength(1);
    expect(
      rpc.mock.calls.filter(([name]) => name === 'list_goal_proposal_history'),
    ).toHaveLength(1);

    view.rerender(sections(client, 2));

    await waitFor(() => {
      expect(
        rpc.mock.calls.filter(([name]) => name === 'list_goal_history'),
      ).toHaveLength(2);
      expect(
        rpc.mock.calls.filter(
          ([name]) => name === 'list_goal_proposal_history',
        ),
      ).toHaveLength(2);
    });
  });
});
