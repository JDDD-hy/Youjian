import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { BrandLogo } from '../components/BrandLogo';
import { loadMembership } from '../lib/membership';
import { ErrorState } from '../components/AsyncState';
import { useOnlineStatus } from '../hooks/useOnlineStatus';

export function WelcomePage() {
  const membership = useQuery({
    queryKey: ['membership'],
    queryFn: loadMembership,
    retry: false,
  });
  const online = useOnlineStatus();
  const active = membership.data?.membership;
  return (
    <main className="welcome-shell">
      <section className="welcome-card" aria-labelledby="welcome-title">
        <BrandLogo className="welcome-logo" />
        <p className="eyebrow">共享专注空间</p>
        <h1 id="welcome-title">友间</h1>
        <p className="tagline">在友间，自有间。</p>
        <p className="welcome-copy">和熟悉的人共享专注状态，不接管你的任务。</p>
        {membership.isLoading ? (
          <div className="welcome-action-placeholder" role="status">
            正在恢复设备身份…
          </div>
        ) : membership.error ? (
          <ErrorState
            title="无法确认当前身份"
            message="为避免创建重复身份，请先重新连接。"
            onRetry={() => void membership.refetch()}
          />
        ) : active ? (
          <Link
            className="button button--primary button--full"
            to={`/space/${active.space_id}`}
          >
            回到友间
          </Link>
        ) : (
          <div className="welcome-actions">
            <Link className="button button--primary button--full" to="/create">
              创建友间
            </Link>
            <Link className="button button--secondary button--full" to="/join">
              等待加入
            </Link>
            <Link className="button button--text button--full" to="/transfer">
              迁移已有身份
            </Link>
          </div>
        )}
        <p className="identity-note">
          无需注册账号。匿名身份只保存在当前设备中。
        </p>
        {membership.data?.latest_disabled_membership && !active && (
          <div className="inline-notice inline-notice--warning" role="status">
            你在「{membership.data.latest_disabled_membership.space_name}
            」的成员身份已被停用。
          </div>
        )}
        {!online && (
          <div className="inline-notice" role="status">
            连接网络后才能创建或加入。
          </div>
        )}
      </section>
    </main>
  );
}
