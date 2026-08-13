import { Suspense } from 'react';
import { NavLink, Outlet, useParams } from 'react-router-dom';
import { PageLoader } from './AsyncState';
import { Icon } from './Icons';
import { BrandLogo } from './BrandLogo';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../lib/api';
import { appPath } from '../lib/appBase';

const items = [
  { suffix: '', label: '首页', icon: 'home' as const, end: true },
  { suffix: '/stats', label: '统计', icon: 'stats' as const },
  { suffix: '/goals', label: '目标', icon: 'target' as const },
  { suffix: '/settings', label: '设置', icon: 'settings' as const },
];

export function AppShell() {
  const { spaceId = '' } = useParams();
  const base = `/space/${spaceId}`;
  const notifications = useQuery({
    queryKey: ['nav-notifications', spaceId],
    queryFn: () =>
      rpc<{ personal: boolean; shared: boolean; proposal: boolean }>(
        'get_nav_notifications',
        { space_id: spaceId },
      ),
    refetchInterval: 30_000,
  });
  const hasGoalNotice = Boolean(
    notifications.data?.data.personal ||
    notifications.data?.data.shared ||
    notifications.data?.data.proposal,
  );
  return (
    <div className="app-layout">
      <aside className="side-nav" aria-label="主导航">
        <div className="side-nav__brand">
          <BrandLogo className="side-nav__logo" />
          友间
        </div>
        <nav>
          {items.map((item) => (
            <NavLink
              key={item.label}
              to={`${base}${item.suffix}`}
              end={item.end}
              className={({ isActive }) =>
                `nav-item${isActive ? ' nav-item--active' : ''}`
              }
            >
              <Icon name={item.icon} />
              <span>{item.label}</span>
              {item.suffix === '/goals' && hasGoalNotice && (
                <span
                  className="nav-notification-dot"
                  aria-label="有新的成就或提案"
                />
              )}
            </NavLink>
          ))}
        </nav>
        <div className="side-nav__note">
          <p>在友间，自有间。</p>
          <a href={appPath('feature-contributors.html')}>
            Contributors <span aria-hidden="true">→</span>
          </a>
        </div>
      </aside>
      <main className="app-content">
        <Suspense
          fallback={
            <div className="page">
              <PageLoader />
            </div>
          }
        >
          <Outlet />
        </Suspense>
      </main>
      <nav className="bottom-nav" aria-label="主导航">
        {items.map((item) => (
          <NavLink
            key={item.label}
            to={`${base}${item.suffix}`}
            end={item.end}
            className={({ isActive }) =>
              `nav-item${isActive ? ' nav-item--active' : ''}`
            }
          >
            <Icon name={item.icon} />
            <span>{item.label}</span>
            {item.suffix === '/goals' && hasGoalNotice && (
              <span
                className="nav-notification-dot"
                aria-label="有新的成就或提案"
              />
            )}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
