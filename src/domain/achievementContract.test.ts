import { describe, expect, it } from 'vitest';
import {
  parseAchievement,
  parseAchievementEvent,
  parseAchievementListResponse,
} from './achievementContract';

describe('achievement RPC contract', () => {
  it('accepts the explicit card, stage, event, and read-target fields', () => {
    const item = parseAchievement({
      achievement_id: 'card-id',
      achievement_type: 'global_timezones',
      card_key: 'global_timezones',
      raw_achievement_key: 'global_timezones',
      scope: 'shared',
      attained_stage: 2,
      stage_key: 'global_timezones_4',
      event_id: 'event-id',
      read_target: { kind: 'shared_card', key: 'global_timezones' },
      tier: 'silver',
      earned_at: '2026-08-14T00:00:00Z',
      notification_eligible: true,
      metadata: {
        timezone_count: 4,
        timezones: ['Asia/Shanghai', 'Europe/Berlin'],
      },
      events: [
        {
          event_id: 'event-id',
          earned_at: '2026-08-14T00:00:00Z',
          is_unlock: true,
          notification_eligible: true,
        },
      ],
    });
    expect(item.read_target).toEqual({
      kind: 'shared_card',
      key: 'global_timezones',
    });
    expect(item.events?.[0]?.is_unlock).toBe(true);
  });

  it('keeps event parsing separate from card parsing', () => {
    expect(
      parseAchievementEvent({
        event_id: 'event-id',
        earned_at: '2026-08-14T00:00:00Z',
        metadata: { effective_seconds: 3600 },
      }).event_id,
    ).toBe('event-id');
  });

  it('rejects a response that omits the stable space and pagination fields', () => {
    expect(() => parseAchievementListResponse({ items: [] })).toThrow();
    expect(() =>
      parseAchievement({ achievement_type: 'global_timezones' }),
    ).toThrow();
  });
});
