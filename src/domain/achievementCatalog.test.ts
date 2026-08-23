import { describe, expect, it } from 'vitest';
import {
  achievementReadIntentKey,
  achievementStrategies,
  achievementStrategy,
  achievementTierFor,
  achievementTitleFor,
  attainedAchievementStage,
  isAchievementUnlockedByCatalog,
  isSharedAchievementReadTarget,
} from './achievementCatalog';
import type { Achievement } from './types';

function achievement(overrides: Partial<Achievement> = {}): Achievement {
  return {
    achievement_id: 'achievement',
    achievement_type: 'global_timezones',
    earned_at: '2026-08-14T00:00:00Z',
    ...overrides,
  };
}

describe('central achievement strategy catalog', () => {
  it('has unique canonical keys and does not alias another canonical key', () => {
    const keys = new Set(achievementStrategies.map((strategy) => strategy.key));
    expect(keys.size).toBe(achievementStrategies.length);
    for (const strategy of achievementStrategies) {
      expect(strategy.legacy_aliases).not.toContain(strategy.key);
      for (const alias of strategy.legacy_aliases)
        expect(keys).not.toContain(alias);
    }
  });

  it('encodes the finalized names, thresholds, and series colors', () => {
    const global = achievementStrategy('global_timezones');
    expect(global?.stage_thresholds.map((stage) => stage.threshold)).toEqual([
      2, 4,
    ]);
    expect(global?.stage_thresholds.map((stage) => stage.title)).toEqual([
      '天涯共此时',
      '五湖四海',
    ]);
    expect(global?.tier_policy).toEqual({
      kind: 'stage',
      tiers: { '1': 'silver', '2': 'gold' },
    });
    expect(achievementStrategy('focus_10000_hours')?.tier_policy).toEqual({
      kind: 'fixed',
      tier: 'diamond',
    });
    expect(
      achievementStrategy('focus_10000_hours')?.stage_thresholds[0]?.threshold,
    ).toBe(600_000);
    expect(
      achievementTitleFor(achievement({ metadata: { timezone_count: 4 } })),
    ).toBe('五湖四海');
    expect(
      achievementTitleFor(
        achievement({ achievement_type: 'focus_10000_hours', count: 1 }),
      ),
    ).toBe('万时户');
    expect(
      achievementTierFor(
        achievement({ achievement_type: 'focus_10000_hours', count: 1 }),
      ),
    ).toBe('diamond');
  });

  it('uses the response stage and read target as authoritative display facts', () => {
    const item = achievement({
      attained_stage: 2,
      read_target: { kind: 'shared_card', key: 'global_timezones' },
    });
    expect(attainedAchievementStage(item)).toBe(2);
    expect(isAchievementUnlockedByCatalog(item)).toBe(true);
    expect(achievementReadIntentKey(item)).toBe('shared_card:global_timezones');
    expect(isSharedAchievementReadTarget(item)).toBe(true);
  });

  it('defines the entertainment focus achievement consistently', () => {
    const strategy = achievementStrategy('joyful_pursuit');
    expect(strategy).toMatchObject({
      evaluator_id: 'focus.category_session',
      icon: 'gamepad_2',
      repeat_policy: 'once',
      tier_policy: { kind: 'fixed', tier: 'gold' },
    });
    expect(strategy?.stage_thresholds).toEqual([
      {
        stage: 1,
        threshold: 10,
        stage_key: 'joyful_pursuit',
        title: '乐在其中',
      },
    ]);
  });
});
