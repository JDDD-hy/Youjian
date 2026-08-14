import type { Achievement, AchievementEvent } from './types';
import {
  achievementConditionFor,
  achievementSeriesFor,
  achievementStagesFor,
  achievementTierFor,
  achievementTitleFor,
  isAchievementUnlockedByCatalog,
  isRepeatableAchievementType,
  achievementStrategy,
} from './achievementCatalog';

export function achievementTier(
  item: Achievement,
): 'bronze' | 'silver' | 'gold' | 'diamond' {
  return achievementTierFor(item);
}

export function achievementTitle(item: Achievement) {
  return achievementTitleFor(item);
}

export function achievementCondition(item: Achievement) {
  return achievementConditionFor(item.achievement_type);
}

export function achievementSeries(item: Achievement) {
  return achievementSeriesFor(item.achievement_type);
}

/**
 * Stages are derived from the current attained metric. Future stages are not
 * rendered just because a strategy defines them.
 */
export function achievementStages(item: Achievement) {
  return achievementStagesFor(item);
}

export function achievementDisplayDate(item: Achievement) {
  return (
    item.last_unlocked_at ??
    item.last_unlock_at ??
    item.unlocked_at ??
    item.unlock_at ??
    item.earned_at
  );
}

export function isAchievementUnlocked(item: Achievement) {
  return isAchievementUnlockedByCatalog(item);
}

export function isRepeatableAchievement(item: Achievement) {
  return item.repeatable ?? isRepeatableAchievementType(item.achievement_type);
}

function isRepeatEvent(event: AchievementEvent) {
  if (event.notification_eligible === false) return true;
  if (event.notification_eligible === true) return false;
  if (event.is_unlock === false || event.is_repeat_event === true) return true;
  if (event.is_event === true && event.is_unlock !== true) return true;
  const kind = event.event_kind ?? event.event_type ?? event.kind;
  return kind === 'event' || kind === 'repeat' || kind === 'repeat_event';
}

/**
 * Only notification-eligible unlocks are shown as achievement history. The
 * fallback preserves old rows that predate the explicit event contract.
 */
export function visibleAchievementEvents(item: Achievement) {
  return item.events?.filter((event) => !isRepeatEvent(event)) ?? [];
}

/** The catalog is the only source for this presentation-level classification. */
export function isPersonalAchievement(type: string) {
  return achievementStrategy(type)?.scope === 'personal';
}
