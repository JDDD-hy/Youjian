import { z } from 'zod';
import type { Achievement, AchievementEvent } from './types';

// Achievement metadata is persisted JSON owned by older and newer writers.
// Keep the read contract open to nested values and explicit nulls so one
// historical payload cannot make the whole achievement list unreadable.
const metadataSchema = z.record(z.string(), z.unknown());

const optionalString = z.preprocess(
  (value) => (value === null ? undefined : value),
  z.string().optional(),
);
const optionalNumber = z.preprocess(
  (value) => (value === null ? undefined : value),
  z.number().optional(),
);
const optionalBoolean = z.preprocess(
  (value) => (value === null ? undefined : value),
  z.boolean().optional(),
);
const optionalMetadata = z.preprocess(
  (value) => (value === null ? undefined : value),
  metadataSchema.optional(),
);

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
    local_date: optionalString,
    source_space_id: optionalString,
    metadata: optionalMetadata,
    is_unlock: optionalBoolean,
    notification_eligible: optionalBoolean,
    is_event: optionalBoolean,
    is_repeat_event: optionalBoolean,
    event_kind: optionalString,
    event_type: optionalString,
    kind: optionalString,
    participants: z.array(participantSchema).optional(),
  })
  .passthrough();

export const achievementSchema = z
  .object({
    achievement_id: z.string(),
    achievement_type: z.string(),
    card_key: optionalString,
    raw_achievement_key: optionalString,
    scope: z.preprocess(
      (value) => (value === null ? undefined : value),
      z.enum(['personal', 'shared']).optional(),
    ),
    attained_stage: optionalNumber,
    stage_key: optionalString,
    event_id: optionalString,
    read_target: achievementReadTargetSchema.nullable().optional(),
    tier: z.preprocess(
      (value) => (value === null ? undefined : value),
      z.enum(['bronze', 'silver', 'gold', 'diamond']).optional(),
    ),
    earned_at: z.string(),
    repeatable: optionalBoolean,
    is_unlock: optionalBoolean,
    notification_eligible: optionalBoolean,
    last_unlock_at: optionalString,
    last_unlocked_at: optionalString,
    unlock_at: optionalString,
    unlocked_at: optionalString,
    metadata: optionalMetadata,
    participants_recorded: optionalBoolean,
    participants: z.array(participantSchema).optional(),
    seen: optionalBoolean,
    first_earned_at: optionalString,
    last_earned_at: optionalString,
    count: optionalNumber,
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
