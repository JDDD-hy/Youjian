import type { ReactNode } from 'react';
import { Icon } from './Icons';

export function PageLoader() {
  return (
    <div className="skeleton-stack" aria-label="正在加载" aria-busy="true">
      <div className="skeleton skeleton--title" />
      <div className="skeleton skeleton--hero" />
      <div className="skeleton skeleton--row" />
      <div className="skeleton skeleton--row" />
    </div>
  );
}

export function ErrorState({
  title = '暂时无法加载',
  message = '请检查网络连接后重新加载。',
  onRetry,
}: {
  title?: string;
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <section className="state-card" role="alert">
      <span className="state-card__icon">
        <Icon name="warning" />
      </span>
      <h2>{title}</h2>
      <p>{message}</p>
      {onRetry && (
        <button
          className="button button--secondary"
          type="button"
          onClick={onRetry}
        >
          重新加载
        </button>
      )}
    </section>
  );
}

export function EmptyState({
  icon = 'sparkle',
  title,
  children,
  action,
}: {
  icon?: 'sparkle' | 'clock' | 'target' | 'people';
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <section className="empty-state">
      <span className="empty-state__icon">
        <Icon name={icon} />
      </span>
      <h3>{title}</h3>
      <div>{children}</div>
      {action}
    </section>
  );
}
