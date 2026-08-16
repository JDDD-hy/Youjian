import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { WelcomePage } from './WelcomePage';

const membership = vi.hoisted(() => ({
  load: vi.fn(),
  cached: vi.fn(),
}));
const pwaInstall = vi.hoisted(() => ({ snapshot: vi.fn() }));

vi.mock('../lib/membership', () => ({
  loadMembership: membership.load,
  readCachedMembership: membership.cached,
}));
vi.mock('../lib/pwaInstall', () => ({
  getPwaInstallSnapshot: pwaInstall.snapshot,
}));

describe('WelcomePage', () => {
  beforeEach(() => {
    cleanup();
    membership.load.mockReset();
    membership.load.mockResolvedValue(null);
    membership.cached.mockReset();
    membership.cached.mockReturnValue(undefined);
    pwaInstall.snapshot.mockReset();
    pwaInstall.snapshot.mockReturnValue({ installed: false });
  });

  it('shows the product message and create action after identity restore', async () => {
    const router = createMemoryRouter([
      { path: '/', element: <WelcomePage /> },
    ]);
    const queryClient = new QueryClient();

    render(
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>,
    );

    expect(screen.getByRole('heading', { name: '友间' })).toBeInTheDocument();
    expect(
      await screen.findByRole('link', { name: '创建友间' }),
    ).toHaveAttribute('href', '/create');
    expect(screen.getByRole('link', { name: '等待加入' })).toHaveAttribute(
      'href',
      '/join',
    );
    expect(screen.getByText(/匿名身份只保存在当前设备中/)).toBeInTheDocument();
  });

  it('returns an installed PWA with an active identity to its space', async () => {
    membership.load.mockResolvedValue({
      membership: {
        member_id: 'member-id',
        space_id: 'space-id',
        display_name: '测试成员',
        role: 'member',
        status: 'active',
      },
      latest_disabled_membership: null,
    });
    pwaInstall.snapshot.mockReturnValue({ installed: true });
    const router = createMemoryRouter([
      { path: '/', element: <WelcomePage /> },
      { path: '/space/:spaceId', element: <div>已回到友间</div> },
    ]);

    render(
      <QueryClientProvider client={new QueryClient()}>
        <RouterProvider router={router} />
      </QueryClientProvider>,
    );

    expect(await screen.findByText('已回到友间')).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/space/space-id');
  });
});
