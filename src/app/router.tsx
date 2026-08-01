import { createBrowserRouter } from 'react-router-dom';
import { lazy } from 'react';
import { SpaceRouteGuard } from '../components/SpaceRouteGuard';
import { CreateSpacePage } from '../routes/CreateSpacePage';
import { InvitePage } from '../routes/InvitePage';
import { PlaceholderPage } from '../routes/PlaceholderPage';
import { WelcomePage } from '../routes/WelcomePage';
import { JoinWaitingPage } from '../routes/JoinWaitingPage';
import { IdentityTransferPage } from '../routes/IdentityTransferPage';
import { repairCurrentAppPath } from '../lib/canonicalPath';

repairCurrentAppPath();

// These are route components; keeping them lazy avoids loading authenticated screens on invite previews.
// eslint-disable-next-line react-refresh/only-export-components
const HomePage = lazy(() =>
  import('../routes/HomePage').then((module) => ({ default: module.HomePage })),
);
// eslint-disable-next-line react-refresh/only-export-components
const StatsPage = lazy(() =>
  import('../routes/StatsPage').then((module) => ({
    default: module.StatsPage,
  })),
);
// eslint-disable-next-line react-refresh/only-export-components
const GoalsPage = lazy(() =>
  import('../routes/GoalsPage').then((module) => ({
    default: module.GoalsPage,
  })),
);
// eslint-disable-next-line react-refresh/only-export-components
const SettingsPage = lazy(() =>
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
        { index: true, element: <HomePage /> },
        { path: 'stats', element: <StatsPage /> },
        { path: 'goals', element: <GoalsPage /> },
        { path: 'settings', element: <SettingsPage /> },
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
