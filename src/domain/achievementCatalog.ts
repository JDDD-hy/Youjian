import catalogJson from './achievementCatalog.json';
import type { Achievement } from './types';

export type AchievementTier = 'bronze' | 'silver' | 'gold' | 'diamond';
export type AchievementScope = 'personal' | 'shared';
export type AchievementRepeatPolicy = 'once' | 'series' | 'daily';

export interface AchievementStageDefinition {
  stage: number;
  threshold: number;
  stage_key: string;
  title: string;
  icon?: string;
}

export interface AchievementStrategy {
  key: string;
  scope: AchievementScope;
  repeat_policy: AchievementRepeatPolicy;
  event_unit: 'session' | 'goal' | 'local_day' | 'member_count';
  metric: string;
  stage_thresholds: AchievementStageDefinition[];
  max_stage_behavior: string;
  notification_policy: string;
  participant_policy: string;
  time_boundary: string;
  legacy_aliases: string[];
  evaluator_id: string;
  counter_scope: string;
  event_key_policy: string;
  activation_boundary: string;
  display_policy: string;
  read_target: string;
  tier_policy:
    | { kind: 'fixed'; tier: AchievementTier }
    | { kind: 'stage'; tiers: Record<string, AchievementTier> };
  icon: string;
  series: string | null;
  condition: string;
}

interface AchievementCatalogFile {
  version: string;
  strategies: AchievementStrategy[];
}

const catalog = catalogJson as AchievementCatalogFile;
const strategies = catalog.strategies;
const byKey = new Map(strategies.map((strategy) => [strategy.key, strategy]));
const aliasToKey = new Map(
  strategies.flatMap((strategy) =>
    strategy.legacy_aliases.map((alias) => [alias, strategy.key] as const),
  ),
);

export const achievementCatalogVersion = catalog.version;
export const achievementStrategies = strategies;

export function canonicalAchievementType(type: string) {
  return aliasToKey.get(type) ?? type;
}

export function achievementStrategy(type: string) {
  return byKey.get(canonicalAchievementType(type));
}

export function isKnownAchievementType(type: string) {
  return Boolean(achievementStrategy(type));
}

export function isPersonalAchievementType(type: string) {
  return achievementStrategy(type)?.scope === 'personal';
}

export function isRepeatableAchievementType(type: string) {
  const repeatPolicy = achievementStrategy(type)?.repeat_policy;
  return repeatPolicy === 'series' || repeatPolicy === 'daily';
}

function metadataNumber(item: Achievement, key: string) {
  const value = Number(item.metadata?.[key] ?? 0);
  return Number.isFinite(value) ? value : 0;
}

export function achievementMetricValue(
  item: Achievement,
  strategy = achievementStrategy(item.achievement_type),
) {
  if (!strategy) return item.count ?? 0;
  if (strategy.metric === 'count') return item.count ?? 0;
  const metricValue = item.metadata?.[strategy.metric];
  return metricValue === undefined
    ? metadataNumber(item, 'stage')
    : metadataNumber(item, strategy.metric);
}

export function attainedAchievementStage(
  item: Achievement,
  strategy = achievementStrategy(item.achievement_type),
) {
  if (!strategy) return 0;
  if (Number.isInteger(item.attained_stage) && item.attained_stage! >= 0) {
    return item.attained_stage!;
  }
  const metric = achievementMetricValue(item, strategy);
  return strategy.stage_thresholds.reduce(
    (stage, candidate) =>
      metric >= candidate.threshold ? Math.max(stage, candidate.stage) : stage,
    0,
  );
}

export function achievementTierFor(
  item: Achievement,
  strategy = achievementStrategy(item.achievement_type),
): AchievementTier {
  if (!strategy) return item.tier ?? 'bronze';
  if (strategy.tier_policy.kind === 'fixed') return strategy.tier_policy.tier;
  const stage = attainedAchievementStage(item, strategy);
  return (
    Object.entries(strategy.tier_policy.tiers)
      .filter(([threshold]) => Number(threshold) <= stage)
      .sort(([left], [right]) => Number(left) - Number(right))
      .at(-1)?.[1] ?? 'bronze'
  );
}

export function achievementTitleFor(
  item: Achievement,
  strategy = achievementStrategy(item.achievement_type),
) {
  if (!strategy) return '共同的光';
  const stage = attainedAchievementStage(item, strategy);
  return (
    strategy.stage_thresholds
      .filter((candidate) => candidate.stage <= stage)
      .sort((left, right) => left.stage - right.stage)
      .at(-1)?.title ??
    strategy.stage_thresholds[0]?.title ??
    '共同的光'
  );
}

export function achievementSeriesFor(
  type: string,
  strategy = achievementStrategy(type),
) {
  return strategy?.series ?? undefined;
}

export function achievementConditionFor(
  type: string,
  strategy = achievementStrategy(type),
) {
  return strategy?.condition ?? '完成对应的共同成就要求。';
}

export function achievementStagesFor(
  item: Achievement,
  strategy = achievementStrategy(item.achievement_type),
) {
  if (!strategy) return undefined;
  const stage = attainedAchievementStage(item, strategy);
  if (stage === 0) return undefined;
  const titles = strategy.stage_thresholds
    .filter((candidate) => candidate.stage <= stage)
    .sort((left, right) => left.stage - right.stage)
    .map((candidate) => candidate.title);
  if (strategy.key === 'focus_milestone' && titles.length > 1) {
    return `累计专注 ${titles.map((title) => title.match(/(\d+)/)?.[1] ?? title).join('、')} 小时`;
  }
  return titles.join('、');
}

export function achievementIconKey(type: string, item?: Achievement) {
  const strategy = achievementStrategy(type);
  if (!strategy) return 'move_right';
  const stage = item ? attainedAchievementStage(item, strategy) : 0;
  return (
    strategy.stage_thresholds
      .filter((candidate) => candidate.stage <= stage && candidate.icon)
      .sort((left, right) => left.stage - right.stage)
      .at(-1)?.icon ??
    strategy.icon ??
    'move_right'
  );
}

export function achievementReadIntentKey(
  item: Pick<Achievement, 'achievement_id' | 'read_target'>,
) {
  const target = item.read_target;
  if (!target) return item.achievement_id;
  return `${target.kind}:${target.key}`;
}

export function isSharedAchievementReadTarget(
  item: Pick<Achievement, 'read_target'>,
) {
  return (
    item.read_target?.kind === 'shared_card' ||
    item.read_target?.kind === 'shared_event'
  );
}

export function isAchievementUnlockedByCatalog(item: Achievement) {
  return attainedAchievementStage(item) > 0;
}
