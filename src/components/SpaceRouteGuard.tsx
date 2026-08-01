import { useQuery } from '@tanstack/react-query';
import { Link, Navigate, useParams } from 'react-router-dom';
import { loadMembership, readCachedMembership } from '../lib/membership';
import { AppShell } from './AppShell';
import { ErrorState, PageLoader } from './AsyncState';

export function SpaceRouteGuard() {
  const { spaceId = '' } = useParams();
  const membership = useQuery({
    queryKey: ['membership'],
    queryFn: loadMembership,
    retry: false,
    placeholderData: readCachedMembership,
  });
  if (membership.isLoading)
    return (
      <main className="form-page">
        <section className="form-card">
          <PageLoader />
        </section>
      </main>
    );
  if (membership.error && !membership.data)
    return (
      <main className="form-page">
        <section className="form-card">
          <ErrorState
            title="无法确认当前身份"
            message="身份尚未恢复，友间内容不会显示。"
            onRetry={() => void membership.refetch()}
          />
        </section>
      </main>
    );
  if (!membership.data) return <Navigate to="/" replace />;
  if (!membership.data.membership) {
    const disabled = membership.data.latest_disabled_membership;
    const voluntarilyLeft = disabled?.end_reason === 'left';
    const dissolved = disabled?.end_reason === 'dissolved';
    return (
      <main className="form-page">
        <section className="form-card">
          <ErrorState
            title={
              voluntarilyLeft
                ? '你已退出这个友间'
                : dissolved
                  ? '这个友间已解散'
                  : disabled
                    ? '成员身份已停用'
                    : '尚未加入友间'
            }
            message={
              voluntarilyLeft
                ? `你可凭「${disabled.space_name}」当前有效的邀请链接重新加入，历史记录仍会保留。`
                : dissolved
                  ? `「${disabled.space_name}」已结束，历史记录仍会保留。`
                  : disabled
                    ? `你已不能进入「${disabled.space_name}」，历史记录仍会保留。`
                : '当前身份没有活动的友间成员关系。'
            }
          />
          <Link className="button button--secondary button--full" to="/">
            返回欢迎页
          </Link>
        </section>
      </main>
    );
  }
  if (membership.data.membership.space_id !== spaceId)
    return (
      <main className="form-page">
        <section className="form-card">
          <ErrorState
            title="无权访问这个友间"
            message="当前身份属于另一个友间。"
          />
          <Link
            className="button button--primary button--full"
            to={`/space/${membership.data.membership.space_id}`}
          >
            回到我的友间
          </Link>
        </section>
      </main>
    );
  return <AppShell />;
}
