import {
  Clock3,
  Hourglass,
  Lamp,
  LampCeiling,
  LampDesk,
  LampWallUp,
  ListChecks,
  MoonStar,
  PersonStanding,
  Target,
  Timer,
  Trees,
  Trophy,
} from 'lucide-react';
import type { Achievement } from '../domain/types';

const iconProps = { 'aria-hidden': true as const, size: 32, strokeWidth: 1.8 };

function sharedAchievementIcon(item: Achievement) {
  if (item.achievement_type === 'together_streak') {
    const days = Number(item.metadata?.days ?? 1);
    return days >= 7 ? (
      <LampCeiling {...iconProps} />
    ) : days >= 3 ? (
      <LampWallUp {...iconProps} />
    ) : (
      <LampDesk {...iconProps} />
    );
  }
  if (item.achievement_type === 'goal_milestone') {
    const goals = Number(item.metadata?.completed_goal_count ?? 1);
    return goals >= 10 ? (
      <Trophy {...iconProps} />
    ) : goals >= 3 ? (
      <ListChecks {...iconProps} />
    ) : (
      <Target {...iconProps} />
    );
  }
  if (item.achievement_type === 'focus_milestone') {
    const minutes = Number(item.metadata?.threshold_minutes ?? 0);
    return minutes >= 6000 ? (
      <Hourglass {...iconProps} />
    ) : minutes >= 3000 ? (
      <Timer {...iconProps} />
    ) : (
      <Clock3 {...iconProps} />
    );
  }
  return <Lamp {...iconProps} />;
}

export function AchievementIcon({ item }: { item: Achievement }) {
  if (item.achievement_type === 'night_owl') {
    return <MoonStar {...iconProps} />;
  }
  if (item.achievement_type === 'solo_focus') {
    const count = item.count ?? 1;
    return count >= 20 ? (
      <Trees {...iconProps} />
    ) : count >= 5 ? (
      <PersonStanding {...iconProps} />
    ) : (
      <Lamp {...iconProps} />
    );
  }
  return sharedAchievementIcon(item);
}
