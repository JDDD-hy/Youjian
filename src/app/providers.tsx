import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { type PropsWithChildren, useState } from 'react';
import { AppErrorBoundary } from '../components/AppErrorBoundary';
import { PWAStatus } from '../components/PWAStatus';

export function AppProviders({ children }: PropsWithChildren) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            retry: 1,
            staleTime: 30_000,
          },
        },
      }),
  );

  return (
    <AppErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <PWAStatus />
        {children}
      </QueryClientProvider>
    </AppErrorBoundary>
  );
}
