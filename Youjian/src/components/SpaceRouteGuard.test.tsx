import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { SpaceRouteGuard } from './SpaceRouteGuard';

const load = vi.hoisted(() => vi.fn());
vi.mock('../lib/membership', () => ({
  loadMembership: load,
  readCachedMembership: () => undefined,
}));

function mount(path: string) {
  const router = createMemoryRouter(
    [{ path: '/space/:spaceId', element: <SpaceRouteGuard /> }],
    { initialEntries: [path] },
  );
  render(
    <QueryClientProvider client={new QueryClient()}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
}

describe('SpaceRouteGuard', () => {
  it('blocks a URL for a different room', async () => {
    load.mockResolvedValue({
      membership: {
        member_id: 'm',
        space_id: 'mine',
        display_name: '我',
        role: 'member',
        status: 'active',
      },
      latest_disabled_membership: null,
    });
    mount('/space/other');
    expect(
      await screen.findByRole('heading', { name: '无权访问这个友间' }),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '回到我的友间' })).toHaveAttribute(
      'href',
      '/space/mine',
    );
  });

  it('shows disabled membership without rendering room content', async () => {
    load.mockResolvedValue({
      membership: null,
      latest_disabled_membership: {
        space_name: '旧友间',
        display_name: '我',
        disabled_at: '2026-07-27T00:00:00Z',
      },
    });
    mount('/space/old');
    expect(
      await screen.findByRole('heading', { name: '成员身份已停用' }),
    ).toBeInTheDocument();
  });
});
