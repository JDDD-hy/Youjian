import '@testing-library/jest-dom/vitest';
import { cleanup, render } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import type { Achievement } from '../domain/types';
import { achievementTier } from '../domain/achievementTier';
import { AchievementIcon } from './AchievementIcon';

afterEach(cleanup);

function iconClass(item: Partial<Achievement>) {
  const { container } = render(
    <AchievementIcon
      item={{
        achievement_id: 'test',
        achievement_type: 'solo_focus',
        earned_at: '2026-08-04T00:00:00Z',
        ...item,
      }}
    />,
  );
  const svg = container.querySelector('svg');
  expect(svg).toHaveAttribute('width', '32');
  expect(svg).toHaveAttribute('height', '32');
  return svg?.getAttribute('class');
}

describe('AchievementIcon', () => {
  it('uses the approved personal achievement icons', () => {
    expect(iconClass({ achievement_type: 'night_owl' })).toContain(
      'lucide-moon-star',
    );
    expect(iconClass({ count: 1 })).toContain('lucide-lamp');
    expect(iconClass({ count: 5 })).toContain('lucide-person-standing');
    expect(iconClass({ count: 20 })).toContain('lucide-trees');
  });

  it('uses distinct approved icons for shared tiers', () => {
    expect(
      iconClass({ achievement_type: 'together_streak', metadata: { days: 1 } }),
    ).toContain('lucide-lamp-desk');
    expect(
      iconClass({ achievement_type: 'together_streak', metadata: { days: 7 } }),
    ).toContain('lucide-lamp-ceiling');
    expect(
      iconClass({
        achievement_type: 'goal_milestone',
        metadata: { completed_goal_count: 10 },
      }),
    ).toContain('lucide-trophy');
  });

  it('derives shared tiers from their thresholds instead of stale RPC tiers', () => {
    expect(
      achievementTier({
        achievement_id: 'three-days',
        achievement_type: 'together_streak',
        earned_at: '2026-08-04T00:00:00Z',
        metadata: { days: 3 },
        tier: 'gold',
      }),
    ).toBe('silver');
  });
});
