import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { WelcomePage } from './WelcomePage';

describe('WelcomePage', () => {
  it('shows the product message and create action after identity restore', async () => {
    const router = createMemoryRouter([
      { path: '/', element: <WelcomePage /> },
    ]);
    const queryClient = new QueryClient();

    render(
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>,
    );

    expect(screen.getByRole('heading', { name: '友间' })).toBeInTheDocument();
    expect(
      await screen.findByRole('link', { name: '创建友间' }),
    ).toHaveAttribute('href', '/create');
    expect(screen.getByText(/匿名身份只保存在当前设备中/)).toBeInTheDocument();
  });
});
