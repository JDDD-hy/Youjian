import { Suspense } from 'react';
import { NavLink, Outlet, useParams } from 'react-router-dom';
import { PageLoader } from './AsyncState';
import { Icon } from './Icons';
import { BrandLogo } from './BrandLogo';

const items = [
  { suffix: '', label: '首页', icon: 'home' as const, end: true },
  { suffix: '/stats', label: '统计', icon: 'stats' as const },
  { suffix: '/goals', label: '目标', icon: 'target' as const },
  { suffix: '/settings', label: '设置', icon: 'settings' as const },
];

export function AppShell() {
  const { spaceId = '' } = useParams();
  const base = `/space/${spaceId}`;
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
            </NavLink>
          ))}
        </nav>
        <p className="side-nav__note">在友间，自有间。</p>
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
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
