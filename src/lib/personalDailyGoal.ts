import type { HomeSnapshot } from '../domain/types';

export interface PersonalDailyGoalResult {
  scope: 'today' | 'future_default';
  target_minutes: number;
  effective_date: string;
}

export function applyPersonalDailyGoal(
  snapshot: HomeSnapshot,
  result: PersonalDailyGoalResult,
): HomeSnapshot {
  const today = snapshot.today;
  return {
    ...snapshot,
    today:
      result.scope === 'today'
        ? {
            ...today,
            goal_target_minutes: result.target_minutes,
            goal_source: 'today_override',
            checkin_target_seconds: result.target_minutes * 60,
            checkin_completed:
              today.credited_focus_seconds >= result.target_minutes * 60,
          }
        : {
            ...today,
            future_default_target_minutes: result.target_minutes,
          },
  };
}
