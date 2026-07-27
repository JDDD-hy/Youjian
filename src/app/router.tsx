import { createBrowserRouter } from 'react-router-dom';
import { PlaceholderPage } from '../routes/PlaceholderPage';
import { WelcomePage } from '../routes/WelcomePage';

export const router = createBrowserRouter([
  { path: '/', element: <WelcomePage /> },
  { path: '/create', element: <PlaceholderPage title="创建友间" /> },
  { path: '/invite/:token', element: <PlaceholderPage title="加入友间" /> },
  { path: '/space/:spaceId', element: <PlaceholderPage title="我们的友间" /> },
  { path: '*', element: <PlaceholderPage title="没有找到这个页面" /> },
]);
