import { describe, expect, it } from 'vitest';
import type { Achievement } from './types';
import {
  achievementCondition,
  achievementDisplayDate,
  isAchievementUnlocked,
  achievementTitle,
  achievementStages,
  visibleAchievementEvents,
} from './achievementTier';

function achievement(overrides: Partial<Achievement> = {}): Achievement {
  return {
    achievement_id: 'achievement',
    achievement_type: 'together_streak',
    earned_at: '2026-08-14T00:00:00Z',
    ...overrides,
  };
}

describe('achievement presentation rules', () => {
  it('shows only stages reached by the current series value', () => {
    expect(
      achievementStages(
        achievement({
          achievement_type: 'solo_focus',
          count: 5,
        }),
      ),
    ).toBe('孤军奋战、独行者');
    expect(
      achievementStages(
        achievement({
          achievement_type: 'focus_milestone',
          metadata: { threshold_minutes: 3000 },
        }),
      ),
    ).toBe('累计专注 10、50 小时');
    expect(
      achievementStages(
        achievement({
          achievement_type: 'fellow_travelers',
          metadata: { stage: 3 },
        }),
      ),
    ).toBe('三人成行');
    expect(
      achievementStages(
        achievement({
          achievement_type: 'focus_milestone',
          metadata: { threshold_minutes: 599 },
        }),
      ),
    ).toBeUndefined();
  });

  it('caps series titles at the latest unlocked stage', () => {
    expect(
      achievementTitle(
        achievement({
          achievement_type: 'together_streak',
          metadata: { days: 4 },
        }),
      ),
    ).toBe('3 日相伴');
    expect(
      achievementTitle(
        achievement({
          achievement_type: 'focus_milestone',
          metadata: { threshold_minutes: 4320 },
        }),
      ),
    ).toBe('累计专注 50 小时');
  });

  it('does not expose a future stage for a one-time achievement', () => {
    expect(
      achievementStages(achievement({ achievement_type: 'living_flame' })),
    ).toBeUndefined();
  });

  it('does not show an earned label for a single-stage achievement', () => {
    expect(
      achievementStages(
        achievement({ achievement_type: 'night_owl', attained_stage: 1 }),
      ),
    ).toBeUndefined();
  });

  it('does not render a focus milestone before its first threshold', () => {
    expect(
      isAchievementUnlocked(
        achievement({
          achievement_type: 'focus_milestone',
          metadata: { threshold_minutes: 599 },
        }),
      ),
    ).toBe(false);
    expect(
      isAchievementUnlocked(
        achievement({
          achievement_type: 'focus_milestone',
          metadata: { threshold_minutes: 600 },
        }),
      ),
    ).toBe(true);
  });

  it('describes living flame as a complete local-day union', () => {
    const condition = achievementCondition(
      achievement({ achievement_type: 'living_flame' }),
    );
    expect(condition).toContain('按空间时区计算');
    expect(condition).toContain('至少两名合格成员');
    expect(condition).toContain('每名合格成员累计有效专注至少 30 分钟');
    expect(condition).toContain('当天 00:00 连续覆盖至次日 00:00');
    expect(condition).toContain('重叠部分只计算一次');
    expect(condition).not.toContain('空档均不超过 30 分钟');
    expect(condition).not.toContain('至少 3 人');
  });

  it('filters repeat events while preserving legacy one-time events', () => {
    const item = achievement({
      achievement_type: 'chance_encounter',
      events: [
        {
          achievement_id: 'unlock',
          earned_at: '2026-08-14T00:00:00Z',
          is_unlock: true,
        },
        {
          achievement_id: 'repeat',
          earned_at: '2026-08-14T01:00:00Z',
          is_unlock: false,
        },
        {
          achievement_id: 'event',
          earned_at: '2026-08-14T02:00:00Z',
          is_event: true,
        },
        {
          achievement_id: 'legacy',
          earned_at: '2026-08-14T03:00:00Z',
        },
      ],
    });

    expect(
      visibleAchievementEvents(item).map((event) => event.achievement_id),
    ).toEqual(['unlock', 'legacy']);
  });

  it('filters notification-ineligible repeat events from repeatable cards', () => {
    const item = achievement({
      achievement_type: 'living_flame',
      events: [
        {
          achievement_id: 'legacy-repeat',
          earned_at: '2026-08-14T01:00:00Z',
          notification_eligible: false,
        },
        {
          achievement_id: 'unlock',
          earned_at: '2026-08-14T02:00:00Z',
          notification_eligible: true,
        },
        {
          achievement_id: 'repeat',
          earned_at: '2026-08-14T03:00:00Z',
          is_unlock: false,
        },
      ],
    });

    expect(
      visibleAchievementEvents(item).map((event) => event.achievement_id),
    ).toEqual(['unlock']);
  });

  it('uses the latest unlock time when the backend provides it', () => {
    expect(
      achievementDisplayDate(
        achievement({
          last_unlocked_at: '2026-08-14T04:00:00Z',
          earned_at: '2026-08-14T05:00:00Z',
        }),
      ),
    ).toBe('2026-08-14T04:00:00Z');
  });
});
