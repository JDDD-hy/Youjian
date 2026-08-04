import type { Achievement } from './types';

export function achievementTier(
  item: Achievement,
): 'bronze' | 'silver' | 'gold' | 'diamond' {
  if (item.achievement_type === 'night_owl') return 'gold';
  if (item.achievement_type === 'solo_focus') {
    const count = item.count ?? 1;
    return count >= 20 ? 'gold' : count >= 5 ? 'silver' : 'bronze';
  }
  if (item.achievement_type === 'promise_keeper') {
    const days = Number(item.metadata?.stage_days ?? 1);
    return days >= 30
      ? 'diamond'
      : days >= 7
        ? 'gold'
        : days >= 3
          ? 'silver'
          : 'bronze';
  }
  if (item.achievement_type === 'together_streak') {
    const days = Number(item.metadata?.days ?? 1);
    return days >= 7 ? 'gold' : days >= 3 ? 'silver' : 'bronze';
  }
  if (item.achievement_type === 'goal_milestone') {
    const count = Number(item.metadata?.completed_goal_count ?? 1);
    return count >= 10 ? 'gold' : count >= 3 ? 'silver' : 'bronze';
  }
  if (item.achievement_type === 'focus_milestone') {
    const minutes = Number(item.metadata?.threshold_minutes ?? 0);
    return minutes >= 6000 ? 'gold' : minutes >= 3000 ? 'silver' : 'bronze';
  }
  return item.tier ?? 'bronze';
}
