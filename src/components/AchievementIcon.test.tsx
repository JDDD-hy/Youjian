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
  it('preserves the approved personal achievement icons', () => {
    expect(iconClass({ achievement_type: 'night_owl' })).toContain(
      'lucide-moon-star',
    );
    expect(iconClass({ count: 1 })).toContain('lucide-pointer');
    expect(iconClass({ count: 5 })).toContain('lucide-person-standing');
    expect(iconClass({ count: 20 })).toContain('lucide-trees');
  });

  it('preserves the approved shared achievement icons', () => {
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
    expect(iconClass({ achievement_type: 'first_goal' })).toContain(
      'lucide-target',
    );
    expect(iconClass({ achievement_type: 'three_days_together' })).toContain(
      'lucide-lamp-desk',
    );
  });

  it('preserves the approved extended Lucide mappings', () => {
    const expected = {
      dawn_walker: 'lucide-sunrise',
      unbroken_focus: 'lucide-move-right',
      double_focus: 'lucide-spline',
      triple_focus: 'lucide-ev-charger',
      three_categories: 'lucide-hexagon',
      return_after_break: 'lucide-list-restart',
      chance_encounter: 'lucide-orbit',
      fellow_travelers: 'lucide-shapes',
      focus_relay: 'lucide-heart-handshake',
      living_flame: 'lucide-flame-kindling',
    };
    for (const [achievement_type, className] of Object.entries(expected)) {
      expect(iconClass({ achievement_type })).toContain(className);
    }
    expect(
      iconClass({
        achievement_type: 'focus_milestone',
        metadata: { threshold_minutes: 600 },
      }),
    ).toContain('lucide-metronome');
    expect(
      iconClass({
        achievement_type: 'fellow_travelers',
        metadata: { stage: 5 },
      }),
    ).toContain('lucide-building-2');
  });

  it('uses the selected Lucide icons for the new achievements', () => {
    const expected: Array<[string, string]> = [
      ['global_timezones', 'lucide-plane'],
      ['task_polisher', 'lucide-wand-sparkles'],
      ['decisive_focus', 'lucide-gavel'],
      ['restless_focus', 'lucide-circle-fading-arrow-up'],
      ['work_diligence', 'lucide-briefcase-business'],
      ['learning_seeker', 'lucide-notebook-pen'],
      ['bookworm', 'lucide-worm'],
      ['mystery_work', 'lucide-badge-question-mark'],
      ['weekend_warrior', 'lucide-award'],
      ['focus_10000_hours', 'lucide-wine'],
      ['first_invitee', 'lucide-sofa'],
      ['full_house', 'lucide-smile-plus'],
    ];
    for (const [achievement_type, className] of expected) {
      expect(iconClass({ achievement_type })).toContain(className);
    }
    expect(iconClass({ achievement_type: 'unknown_unmapped_key' })).toContain(
      'lucide-move-right',
    );
    expect(
      iconClass({ achievement_type: 'global_timezones', attained_stage: 2 }),
    ).toContain('lucide-earth');
  });

  it('uses diamond for the fourth promise stage', () => {
    expect(
      achievementTier({
        achievement_id: 'promise',
        achievement_type: 'promise_keeper',
        earned_at: '2026-08-05T00:00:00Z',
        metadata: { stage_days: 30 },
      }),
    ).toBe('diamond');
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
