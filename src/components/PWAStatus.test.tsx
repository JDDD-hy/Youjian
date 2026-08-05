import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PWAStatus } from './PWAStatus';
import { resetPwaInstallStateForTests } from '../lib/pwaInstall';

const pwa = vi.hoisted(() => ({
  options: undefined as
    | {
        onNeedRefresh?: () => void;
        onOfflineReady?: () => void;
        onRegisterError?: () => void;
        onRegisteredSW?: (
          swUrl: string,
          registration: ServiceWorkerRegistration | undefined,
        ) => void;
      }
    | undefined,
  update: vi.fn(() => Promise.resolve()),
  registrationUpdate: vi.fn(() => Promise.resolve()),
}));
vi.mock('virtual:pwa-register', () => ({
  registerSW: (options: {
    onNeedRefresh?: () => void;
    onOfflineReady?: () => void;
    onRegisterError?: () => void;
    onRegisteredSW?: (
      swUrl: string,
      registration: ServiceWorkerRegistration | undefined,
    ) => void;
  }) => {
    pwa.options = options;
    options.onRegisteredSW?.('/sw.js', {
      update: pwa.registrationUpdate,
    } as unknown as ServiceWorkerRegistration);
    return pwa.update;
  },
}));
const membership = vi.hoisted(() => vi.fn());
const rpc = vi.hoisted(() => vi.fn());
vi.mock('../lib/membership', () => ({ loadMembership: membership }));
vi.mock('../lib/api', () => ({ rpc }));

function mount(client = new QueryClient()) {
  return render(
    <QueryClientProvider client={client}>
      <PWAStatus />
    </QueryClientProvider>,
  );
}

describe('PWAStatus', () => {
  beforeEach(() => {
    cleanup();
    resetPwaInstallStateForTests();
    membership.mockReset();
    membership.mockResolvedValue(null);
    rpc.mockReset();
    pwa.update.mockClear();
    pwa.registrationUpdate.mockClear();
  });
  it('offers the captured install prompt', async () => {
    mount();
    const prompt = vi.fn(() => Promise.resolve());
    const event = Object.assign(new Event('beforeinstallprompt'), {
      prompt,
      userChoice: Promise.resolve({ outcome: 'accepted' as const }),
    });
    act(() => {
      window.dispatchEvent(event);
    });
    fireEvent.click(await screen.findByRole('button', { name: '安装' }));
    expect(prompt).toHaveBeenCalledOnce();
  });

  it('defers a service-worker reload while focus is active', async () => {
    const client = new QueryClient();
    client.setQueryData(['home', 'space'], {
      snapshot: { my_session: { status: 'focusing' } },
    });
    mount(client);
    act(() => pwa.options?.onNeedRefresh?.());
    expect(await screen.findByRole('button', { name: '更新' })).toBeDisabled();
    expect(screen.getByText(/当前专注结束后/)).toBeInTheDocument();
  });

  it('checks the server before offering a reload outside the home route', async () => {
    membership.mockResolvedValue({
      membership: { space_id: 'space' },
      latest_disabled_membership: null,
    });
    rpc.mockResolvedValue({
      data: { my_session: { status: 'paused' } },
      serverNow: '2026-07-28T00:00:00Z',
      requestId: 'request',
    });
    mount();
    act(() => pwa.options?.onNeedRefresh?.());
    expect(
      await screen.findByText(/当前专注结束后即可更新/),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '更新' })).toBeDisabled();
    expect(pwa.update).not.toHaveBeenCalled();
  });

  it('announces offline shell behavior reactively', () => {
    Object.defineProperty(navigator, 'onLine', {
      configurable: true,
      value: false,
    });
    mount();
    expect(screen.getByText(/业务数据不会离线写入/)).toBeInTheDocument();
    Object.defineProperty(navigator, 'onLine', {
      configurable: true,
      value: true,
    });
  });

  it('announces when the offline shell is ready', () => {
    mount();
    act(() => pwa.options?.onOfflineReady?.());
    expect(screen.getByText('离线应用外壳已准备好。')).toBeInTheDocument();
  });

  it('distinguishes service-worker registration failure', () => {
    mount();
    act(() => pwa.options?.onRegisterError?.());
    expect(screen.getByRole('alert')).toHaveTextContent('服务注册失败');
  });

  it('checks for an update when the installed client returns to the foreground', () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    mount();
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    expect(pwa.registrationUpdate).toHaveBeenCalledTimes(1);
  });
});
