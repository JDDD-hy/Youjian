import { z } from 'zod';
import type { Achievement, AchievementEvent } from './types';

const metadataValueSchema = z.union([
  z.string(),
  z.number(),
  z.boolean(),
  z.array(z.string()),
]);

const metadataSchema = z.record(z.string(), metadataValueSchema);

const participantSchema = z.object({
  member_id: z.string(),
  display_name: z.string(),
  participation_days: z.number(),
});

export const achievementReadTargetSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('personal_tab'), key: z.literal('personal') }),
  z.object({ kind: z.literal('shared_card'), key: z.string() }),
  z.object({
    kind: z.literal('shared_event'),
    key: z.string(),
    ids: z.array(z.string()),
  }),
]);

export const achievementEventSchema = z
  .object({
    achievement_id: z.string().optional(),
    event_id: z.string().optional(),
    earned_at: z.string(),
    local_date: z.string().optional(),
    source_space_id: z.string().optional(),
    metadata: metadataSchema.optional(),
    is_unlock: z.boolean().optional(),
    notification_eligible: z.boolean().optional(),
    is_event: z.boolean().optional(),
    is_repeat_event: z.boolean().optional(),
    event_kind: z.string().optional(),
    event_type: z.string().optional(),
    kind: z.string().optional(),
    participants: z.array(participantSchema).optional(),
  })
  .passthrough();

export const achievementSchema = z
  .object({
    achievement_id: z.string(),
    achievement_type: z.string(),
    card_key: z.string().optional(),
    raw_achievement_key: z.string().optional(),
    scope: z.enum(['personal', 'shared']).optional(),
    attained_stage: z.number().optional(),
    stage_key: z.string().optional(),
    event_id: z.string().optional(),
    read_target: achievementReadTargetSchema.optional(),
    tier: z.enum(['bronze', 'silver', 'gold', 'diamond']).optional(),
    earned_at: z.string(),
    repeatable: z.boolean().optional(),
    is_unlock: z.boolean().optional(),
    notification_eligible: z.boolean().optional(),
    last_unlock_at: z.string().optional(),
    last_unlocked_at: z.string().optional(),
    unlock_at: z.string().optional(),
    unlocked_at: z.string().optional(),
    metadata: metadataSchema.optional(),
    participants_recorded: z.boolean().optional(),
    participants: z.array(participantSchema).optional(),
    seen: z.boolean().optional(),
    first_earned_at: z.string().optional(),
    last_earned_at: z.string().optional(),
    count: z.number().optional(),
    events: z.array(achievementEventSchema).optional(),
  })
  .passthrough();

export const achievementListResponseSchema = z.object({
  space_id: z.string(),
  items: z.array(achievementSchema),
  next_cursor: z.string().nullable(),
});

export function parseAchievement(value: unknown): Achievement {
  return achievementSchema.parse(value);
}

export function parseAchievementEvent(value: unknown): AchievementEvent {
  return achievementEventSchema.parse(value);
}

export function parseAchievementListResponse(value: unknown) {
  return achievementListResponseSchema.parse(value) as {
    space_id: string;
    items: Achievement[];
    next_cursor: string | null;
  };
}
