import { createBrowserRouter } from 'react-router-dom';
import { SpaceRouteGuard } from '../components/SpaceRouteGuard';
import { RouteErrorPage } from '../components/RouteErrorPage';
import { CreateSpacePage } from '../routes/CreateSpacePage';
import { InvitePage } from '../routes/InvitePage';
import { PlaceholderPage } from '../routes/PlaceholderPage';
import { WelcomePage } from '../routes/WelcomePage';
import { JoinWaitingPage } from '../routes/JoinWaitingPage';
import { IdentityTransferPage } from '../routes/IdentityTransferPage';
import { repairCurrentAppPath } from '../lib/canonicalPath';
import { lazyRoute } from '../lib/lazyRoute';

repairCurrentAppPath();

// These are route components; keeping them lazy avoids loading authenticated screens on invite previews.
const HomePage = lazyRoute('home', () =>
  import('../routes/HomePage').then((module) => ({ default: module.HomePage })),
);
const StatsPage = lazyRoute('stats', () =>
  import('../routes/StatsPage').then((module) => ({
    default: module.StatsPage,
  })),
);
const GoalsPage = lazyRoute('goals', () =>
  import('../routes/GoalsPage').then((module) => ({
    default: module.GoalsPage,
  })),
);
const SettingsPage = lazyRoute('settings', () =>
  import('../routes/SettingsPage').then((module) => ({
    default: module.SettingsPage,
  })),
);

export const router = createBrowserRouter(
  [
    { path: '/', element: <WelcomePage /> },
    { path: '/create', element: <CreateSpacePage /> },
    { path: '/join', element: <JoinWaitingPage /> },
    { path: '/transfer', element: <IdentityTransferPage /> },
    { path: '/invite/:token', element: <InvitePage /> },
    {
      path: '/space/:spaceId',
      element: <SpaceRouteGuard />,
      children: [
        {
          index: true,
          element: <HomePage />,
          errorElement: <RouteErrorPage />,
        },
        {
          path: 'stats',
          element: <StatsPage />,
          errorElement: <RouteErrorPage />,
        },
        {
          path: 'goals',
          element: <GoalsPage />,
          errorElement: <RouteErrorPage />,
        },
        {
          path: 'settings',
          element: <SettingsPage />,
          errorElement: <RouteErrorPage />,
        },
      ],
    },
    { path: '*', element: <PlaceholderPage title="没有找到这个页面" /> },
  ],
  {
    basename:
      import.meta.env.BASE_URL === '/'
        ? '/'
        : import.meta.env.BASE_URL.replace(/\/$/, ''),
  },
);
