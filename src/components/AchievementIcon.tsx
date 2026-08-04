import {
  Anvil,
  Building2,
  Droplet,
  EvCharger,
  FlameKindling,
  HeartHandshake,
  Hexagon,
  Hourglass,
  LampCeiling,
  LampDesk,
  LampWallUp,
  ListChecks,
  ListRestart,
  Metronome,
  MoveRight,
  MoonStar,
  Orbit,
  PersonStanding,
  Pointer,
  Shapes,
  Spline,
  Sprout,
  Stamp,
  Sunrise,
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
      <Metronome {...iconProps} />
    );
  }
  if (item.achievement_type === 'fellow_travelers') {
    return Number(item.metadata?.stage ?? 3) >= 5 ? (
      <Building2 {...iconProps} />
    ) : (
      <Shapes {...iconProps} />
    );
  }
  const icons = {
    dawn_walker: Sunrise,
    unbroken_focus: MoveRight,
    double_focus: Spline,
    triple_focus: EvCharger,
    three_categories: Hexagon,
    promise_keeper: Stamp,
    return_after_break: ListRestart,
    chance_encounter: Orbit,
    focus_relay: HeartHandshake,
    living_flame: FlameKindling,
  } as const;
  const Icon = icons[item.achievement_type as keyof typeof icons] ?? Building2;
  return <Icon {...iconProps} />;
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
      <Pointer {...iconProps} />
    );
  }
  if (item.achievement_type === 'promise_keeper') {
    const days = Number(item.metadata?.stage_days ?? 1);
    if (days >= 30) return <Anvil {...iconProps} />;
    if (days >= 7) return <Droplet {...iconProps} />;
    if (days >= 3) return <Sprout {...iconProps} />;
    return <Stamp {...iconProps} />;
  }
  return sharedAchievementIcon(item);
}
