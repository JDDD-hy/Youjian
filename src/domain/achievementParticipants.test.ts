import { describe, expect, it } from 'vitest';
import { uniqueAchievementParticipantCount } from './achievementParticipants';

describe('uniqueAchievementParticipantCount', () => {
  it('counts people once across repeated achievement events', () => {
    expect(
      uniqueAchievementParticipantCount({
        achievement_id: 'together_streak',
        achievement_type: 'together_streak',
        earned_at: '2026-08-04T12:00:00Z',
        events: [
          {
            earned_at: '2026-08-04T12:00:00Z',
            participants: [
              {
                member_id: 'jade',
                display_name: 'jade',
                participation_days: 1,
              },
              { member_id: 'ju', display_name: 'JU', participation_days: 1 },
            ],
          },
          {
            earned_at: '2026-08-02T12:00:00Z',
            participants: [
              {
                member_id: 'jade',
                display_name: 'jade',
                participation_days: 1,
              },
              { member_id: 'ju', display_name: 'JU', participation_days: 1 },
            ],
          },
        ],
      }),
    ).toBe(2);
  });

  it('falls back to the card participant snapshot for legacy responses', () => {
    expect(
      uniqueAchievementParticipantCount({
        achievement_id: 'legacy',
        achievement_type: 'first_goal',
        earned_at: '2026-08-01T12:00:00Z',
        participants: [
          { member_id: 'jade', display_name: 'jade', participation_days: 1 },
          { member_id: 'ju', display_name: 'JU', participation_days: 1 },
        ],
      }),
    ).toBe(2);
  });
});
