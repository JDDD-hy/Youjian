import {
  Anvil,
  Award,
  BookMarked,
  BookOpen,
  BadgeQuestionMark,
  BriefcaseBusiness,
  Building2,
  CircleFadingArrowUp,
  Cog,
  Gamepad2,
  Droplet,
  Dumbbell,
  EvCharger,
  Earth,
  FlameKindling,
  Gem,
  Globe2,
  Hammer,
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
  Plane,
  PersonStanding,
  Pointer,
  Shapes,
  SmilePlus,
  Sparkles,
  Spline,
  Sprout,
  Stamp,
  Sunrise,
  Target,
  Timer,
  Trees,
  Trophy,
  WandSparkles,
  Wine,
  Worm,
  Gavel,
  Sofa,
  NotebookPen,
} from 'lucide-react';
import type { Achievement } from '../domain/types';
import {
  achievementIconKey,
  canonicalAchievementType,
} from '../domain/achievementCatalog';

const iconProps = { 'aria-hidden': true as const, size: 32, strokeWidth: 1.8 };

function sharedAchievementIcon(item: Achievement) {
  const type = canonicalAchievementType(item.achievement_type);
  if (type === 'together_streak') {
    const days = Number(item.metadata?.days ?? 1);
    return days >= 7 ? (
      <LampCeiling {...iconProps} />
    ) : days >= 3 ? (
      <LampWallUp {...iconProps} />
    ) : (
      <LampDesk {...iconProps} />
    );
  }
  if (type === 'goal_milestone') {
    const goals = Number(item.metadata?.completed_goal_count ?? 1);
    return goals >= 10 ? (
      <Trophy {...iconProps} />
    ) : goals >= 3 ? (
      <ListChecks {...iconProps} />
    ) : (
      <Target {...iconProps} />
    );
  }
  if (type === 'focus_milestone') {
    const minutes = Number(item.metadata?.threshold_minutes ?? 0);
    return minutes >= 6000 ? (
      <Hourglass {...iconProps} />
    ) : minutes >= 3000 ? (
      <Timer {...iconProps} />
    ) : (
      <Metronome {...iconProps} />
    );
  }
  if (type === 'fellow_travelers') {
    return Number(item.metadata?.stage ?? 3) >= 5 ? (
      <Building2 {...iconProps} />
    ) : (
      <Shapes {...iconProps} />
    );
  }
  const icons = {
    sunrise: Sunrise,
    move_right: MoveRight,
    spline: Spline,
    ev_charger: EvCharger,
    hexagon: Hexagon,
    stamp: Stamp,
    list_restart: ListRestart,
    orbit: Orbit,
    heart_handshake: HeartHandshake,
    flame_kindling: FlameKindling,
    globe: Globe2,
    plane: Plane,
    earth: Earth,
    hammer: Hammer,
    anvil: Anvil,
    wand_sparkles: WandSparkles,
    gavel: Gavel,
    circle_fading_arrow_up: CircleFadingArrowUp,
    metronome: Metronome,
    briefcase: BriefcaseBusiness,
    briefcase_business: BriefcaseBusiness,
    book_open: BookOpen,
    notebook_pen: NotebookPen,
    book_marked: BookMarked,
    worm: Worm,
    sparkles: Sparkles,
    badge_question_mark: BadgeQuestionMark,
    gamepad_2: Gamepad2,
    cog: Cog,
    dumbbell: Dumbbell,
    award: Award,
    trees: Trees,
    gem: Gem,
    wine: Wine,
    person_standing: PersonStanding,
    sofa: Sofa,
    smile_plus: SmilePlus,
    building: Building2,
  } as const;
  const Icon =
    icons[
      achievementIconKey(item.achievement_type, item) as keyof typeof icons
    ] ?? MoveRight;
  return <Icon {...iconProps} />;
}

export function AchievementIcon({ item }: { item: Achievement }) {
  const type = canonicalAchievementType(item.achievement_type);
  if (type === 'night_owl') {
    return <MoonStar {...iconProps} />;
  }
  if (type === 'solo_focus') {
    const count = item.count ?? 1;
    return count >= 20 ? (
      <Trees {...iconProps} />
    ) : count >= 5 ? (
      <PersonStanding {...iconProps} />
    ) : (
      <Pointer {...iconProps} />
    );
  }
  if (type === 'promise_keeper') {
    const days = Number(item.metadata?.stage_days ?? 1);
    if (days >= 30) return <Anvil {...iconProps} />;
    if (days >= 7) return <Droplet {...iconProps} />;
    if (days >= 3) return <Sprout {...iconProps} />;
    return <Stamp {...iconProps} />;
  }
  return sharedAchievementIcon(item);
}
