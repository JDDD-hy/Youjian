import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { registerSW } from 'virtual:pwa-register';
import type { HomeSnapshot } from '../domain/types';
import { useOnlineStatus } from '../hooks/useOnlineStatus';
import { rpc } from '../lib/api';
import { loadMembership } from '../lib/membership';
import {
  type InstallPromptEvent,
  getPwaInstallSnapshot,
  markPwaInstalled,
  promptPwaInstall,
  setInstallPrompt,
  subscribePwaInstall,
} from '../lib/pwaInstall';

export function PWAStatus() {
  const queryClient = useQueryClient();
  const online = useOnlineStatus();
  const installState = useSyncExternalStore(
    subscribePwaInstall,
    getPwaInstallSnapshot,
    getPwaInstallSnapshot,
  );
  const [updateReady, setUpdateReady] = useState(false);
  const [offlineReady, setOfflineReady] = useState(false);
  const [updateError, setUpdateError] = useState<
    'registration' | 'focus_check' | 'apply' | null
  >(null);
  const updateSW = useRef<
    ((reloadPage?: boolean) => Promise<void>) | undefined
  >(undefined);
  const cachedActiveFocus = useSyncExternalStore(
    (notify) => queryClient.getQueryCache().subscribe(notify),
    () =>
      queryClient
        .getQueriesData<{ snapshot: HomeSnapshot }>({ queryKey: ['home'] })
        .some(
          ([, value]) =>
            value?.snapshot.my_session?.status === 'focusing' ||
            value?.snapshot.my_session?.status === 'paused',
        ),
    () => false,
  );
  const focusGuard = useQuery({
    queryKey: ['pwa-update-focus-guard'],
    enabled: updateReady && online,
    staleTime: 0,
    retry: false,
    queryFn: async () => {
      const membership = await loadMembership();
      if (!membership?.membership) return false;
      const { data } = await rpc<HomeSnapshot>('get_home_snapshot', {
        space_id: membership.membership.space_id,
      });
      return (
        data.my_session?.status === 'focusing' ||
        data.my_session?.status === 'paused'
      );
    },
  });
  const activeFocus = cachedActiveFocus || focusGuard.data === true;
  const checkingFocus = updateReady && online && focusGuard.isPending;
  useEffect(() => {
    const update = registerSW({
      immediate: true,
      onNeedRefresh: () => setUpdateReady(true),
      onOfflineReady: () => setOfflineReady(true),
      onRegisterError: () => setUpdateError('registration'),
    });
    updateSW.current = update;
    const beforeInstall = (event: Event) => {
      event.preventDefault();
      setInstallPrompt(event as InstallPromptEvent);
    };
    const appInstalled = () => markPwaInstalled();
    window.addEventListener('beforeinstallprompt', beforeInstall);
    window.addEventListener('appinstalled', appInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', beforeInstall);
      window.removeEventListener('appinstalled', appInstalled);
    };
  }, []);
  const installApp = async () => {
    await promptPwaInstall();
  };
  const applyUpdate = async () => {
    setUpdateError(null);
    const result = await focusGuard.refetch();
    if (result.isError) {
      setUpdateError('focus_check');
      return;
    }
    if (result.data) return;
    try {
      await updateSW.current?.(true);
    } catch {
      setUpdateError('apply');
    }
  };
  return (
    <div className="app-status">
      {!online && (
        <div className="app-status__bar">
          当前离线。已缓存的应用外壳仍可使用，业务数据不会离线写入。
        </div>
      )}
      {offlineReady && online && (
        <div className="app-status__prompt">
          <span>离线应用外壳已准备好。</span>
          <button
            aria-label="关闭离线提示"
            onClick={() => setOfflineReady(false)}
          >
            ×
          </button>
        </div>
      )}
      {installState.promptEvent && !installState.installed && (
        <div className="app-status__prompt">
          <span>将友间安装到设备，打开更方便。</span>
          <button onClick={() => void installApp()}>安装</button>
          <button
            aria-label="暂不安装"
            onClick={() => setInstallPrompt(undefined)}
          >
            ×
          </button>
        </div>
      )}
      {updateReady && (
        <div className="app-status__prompt">
          <span>
            {activeFocus
              ? '新版本已准备好，当前专注结束后即可更新。'
              : '新版本已准备好。'}
          </span>
          <button
            disabled={activeFocus || checkingFocus || focusGuard.isError}
            onClick={() => void applyUpdate()}
          >
            {checkingFocus ? '正在确认…' : '更新'}
          </button>
          <button aria-label="稍后更新" onClick={() => setUpdateReady(false)}>
            ×
          </button>
        </div>
      )}
      {(updateError || (updateReady && focusGuard.isError)) && (
        <div className="app-status__bar" role="alert">
          {updateError === 'registration'
            ? '离线应用服务注册失败；在线功能仍可使用。'
            : updateError === 'apply'
              ? '新版本安装失败，当前版本仍可继续使用。'
              : '暂时无法确认专注状态，更新尚未执行。'}
        </div>
      )}
    </div>
  );
}
