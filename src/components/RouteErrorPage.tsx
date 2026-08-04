import { ErrorState } from './AsyncState';

export function RouteErrorPage() {
  return (
    <main className="page">
      <ErrorState
        title="页面版本已经更新"
        message="当前页面仍在使用旧版本资源，请重新加载后继续。"
        onRetry={() => window.location.reload()}
      />
    </main>
  );
}
