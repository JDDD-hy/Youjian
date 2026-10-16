import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
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

describe('goal history panels', () => {
  afterEach(cleanup);
  beforeEach(() => {
    rpc.mockReset();
    rpc.mockImplementation(
      (_name: string, params: { kind: string; page: number }) =>
        Promise.resolve({
          data: {
            space_id: 'space',
            page: params.page,
            page_count: 2,
            total_count: 5,
            items:
              params.kind === 'goals'
                ? params.page === 1
                  ? [goal(1), goal(2), goal(3)]
                  : [goal(4), goal(5)]
                : params.page === 1
                  ? [proposal(1), proposal(2), proposal(3), proposal(4)]
                  : [proposal(5)],
          },
        }),
    );
  });
  it('loads only the opened panel and only the requested page', async () => {
    const { view } = mount();
    expect(rpc).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: '过往目标 ›' }));
    await waitFor(() =>
      expect(view.container.querySelectorAll('.goal-card')).toHaveLength(3),
    );
    expect(rpc).toHaveBeenCalledWith('list_goal_history_page', {
      space_id: 'space',
      kind: 'goals',
      page: 1,
      limit: 3,
    });
    fireEvent.click(screen.getByRole('button', { name: '下一页 ›' }));
    await waitFor(() =>
      expect(view.container.querySelectorAll('.goal-card')).toHaveLength(2),
    );
    expect(rpc).toHaveBeenLastCalledWith('list_goal_history_page', {
      space_id: 'space',
      kind: 'goals',
      page: 2,
      limit: 3,
    });
    expect(screen.getByRole('button', { name: '下一页 ›' })).toBeDisabled();
  });
  it('rejects invalid page input without making a request and accepts a direct jump', async () => {
    mount();
    fireEvent.click(screen.getByRole('button', { name: '已结束提案 ›' }));
    await screen.findByText('共 5 条 · 第 1 / 2 页');
    const input = screen.getByRole('textbox', { name: '跳转页码' });
    for (const value of [
      '',
      ' ',
      '0',
      '-1',
      '3',
      '1.5',
      '1e0',
      'NaN',
      'Infinity',
      'abc',
      '+1',
      '0x1',
      '２',
      '999999999999999999999',
    ]) {
      fireEvent.change(input, { target: { value } });
      fireEvent.submit(input.closest('form')!);
      expect(input).toHaveAttribute('aria-invalid', 'true');
    }
    expect(rpc).toHaveBeenCalledTimes(1);
    fireEvent.change(input, { target: { value: ' 02 ' } });
    fireEvent.submit(input.closest('form')!);
    await screen.findByText('共 5 条 · 第 2 / 2 页');
    expect(rpc).toHaveBeenLastCalledWith('list_goal_history_page', {
      space_id: 'space',
      kind: 'proposals',
      page: 2,
      limit: 4,
    });
  });
  it('refreshes an open panel after the maintained snapshot changes', async () => {
    const { client, view } = mount();
    fireEvent.click(screen.getByRole('button', { name: '过往目标 ›' }));
    await screen.findByText('共 5 条 · 第 1 / 2 页');
    view.rerender(sections(client, 2));
    await waitFor(() => expect(rpc).toHaveBeenCalledTimes(2));
  });
  it('shows empty histories without invalid page numbers', async () => {
    rpc.mockResolvedValue({
      data: {
        space_id: 'space',
        page: 1,
        page_count: 1,
        total_count: 0,
        items: [],
      },
    });
    mount();
    fireEvent.click(screen.getByRole('button', { name: '过往目标 ›' }));
    await screen.findByText('暂无过往目标。');
    expect(screen.getByRole('button', { name: '下一页 ›' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '‹ 上一页' })).toBeDisabled();
  });
  it('shows a retry action when history retrieval fails', async () => {
    rpc.mockRejectedValueOnce(new Error('offline'));
    mount();
    fireEvent.click(screen.getByRole('button', { name: '过往目标 ›' }));
    await screen.findByRole('heading', { name: '无法加载过往目标' });
    fireEvent.click(screen.getByRole('button', { name: '重新加载' }));
    await screen.findByText('共 5 条 · 第 1 / 2 页');
  });
});
