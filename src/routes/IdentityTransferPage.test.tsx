import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { IdentityTransferPage } from './IdentityTransferPage';
import { ensureAnonymousSession, rpc } from '../lib/api';
import { loadMembership } from '../lib/membership';

vi.mock('../lib/api', () => ({
  ensureAnonymousSession: vi.fn(),
  rpc: vi.fn(),
}));
vi.mock('../lib/membership', () => ({ loadMembership: vi.fn() }));
vi.mock('../components/TurnstileField', () => ({ TurnstileField: () => null }));
vi.mock('../hooks/useOnlineStatus', () => ({ useOnlineStatus: () => true }));

function setup() {
  const client = new QueryClient();
  client.setQueryData(['membership'], null);
  const router = createMemoryRouter(
    [
      { path: '/transfer', element: <IdentityTransferPage /> },
      { path: '/space/:spaceId', element: <p>进入成功</p> },
    ],
    { initialEntries: ['/transfer'] },
  );
  render(
    <QueryClientProvider client={client}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
  fireEvent.change(screen.getByRole('textbox'), {
    target: { value: 'a'.repeat(22) },
  });
  fireEvent.click(screen.getByRole('button', { name: '恢复到这台设备' }));
  return client;
}

describe('IdentityTransferPage', () => {
  beforeEach(() => {
    vi.resetAllMocks();
    vi.mocked(ensureAnonymousSession).mockResolvedValue({} as never);
    vi.mocked(rpc).mockResolvedValue({ data: { transferred: true } } as never);
  });

  it('keeps recovery successful when membership loading fails and retries without consuming the code again', async () => {
    vi.mocked(loadMembership)
      .mockRejectedValueOnce(new Error('timeout'))
      .mockResolvedValueOnce({
        membership: { space_id: 'room' },
        latest_disabled_membership: null,
      } as never);
    const client = setup();
    expect(await screen.findByRole('status')).toHaveTextContent('身份恢复成功');
    fireEvent.click(await screen.findByRole('button', { name: '进入友间' }));
    expect(await screen.findByText('进入成功')).toBeInTheDocument();
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(client.getQueryData(['membership'])).toMatchObject({
      membership: { space_id: 'room' },
    });
  });

  it('does not claim success when redemption fails', async () => {
    vi.mocked(rpc).mockRejectedValueOnce(new Error('恢复码无效'));
    setup();
    await waitFor(() =>
      expect(screen.getByText('恢复码无效')).toBeInTheDocument(),
    );
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    expect(loadMembership).not.toHaveBeenCalled();
  });
});
