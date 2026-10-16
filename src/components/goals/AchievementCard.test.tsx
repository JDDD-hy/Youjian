import '@testing-library/jest-dom/vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, expect, it } from 'vitest';
import { AchievementCard } from './AchievementCard';

afterEach(cleanup);

it('keeps names inside the profile and restores focus after closing', () => {
  render(
    <AchievementCard
      item={{
        achievement_id: 'night',
        achievement_type: 'night_owl',
        earned_at: '2026-10-15T00:36:00Z',
      }}
    />,
  );
  const trigger = screen.getByRole('button', { name: '查看挑灯夜战资料卡' });
  expect(trigger).not.toHaveTextContent('挑灯夜战');
  trigger.focus();
  fireEvent.click(trigger);
  expect(screen.getByRole('heading', { name: '挑灯夜战' })).toBeVisible();
  expect(screen.queryByText(/共同达成/)).not.toBeInTheDocument();
  expect(screen.queryByRole('tooltip')).not.toBeInTheDocument();
  fireEvent.keyDown(document, { key: 'Escape' });
  expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
  expect(trigger).toHaveFocus();
});

it('preserves missing participant records and closes with the X', () => {
  render(
    <AchievementCard
      item={{
        achievement_id: 'shared',
        achievement_type: 'together_streak',
        metadata: { days: 7 },
        earned_at: '2026-10-15T00:36:00Z',
      }}
    />,
  );
  fireEvent.click(screen.getByRole('button', { name: '查看7 日相伴资料卡' }));
  expect(screen.getByText(/早期成就的参与成员记录暂缺/)).toBeVisible();
  fireEvent.click(screen.getByRole('button', { name: '关闭成就资料卡' }));
  expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
});
