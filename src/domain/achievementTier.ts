import type { Achievement, AchievementEvent } from './types';

function metadataNumber(item: Achievement, key: string, fallback: number) {
  const value = Number(item.metadata?.[key] ?? fallback);
  return Number.isFinite(value) ? value : fallback;
}

export function achievementTier(
  item: Achievement,
): 'bronze' | 'silver' | 'gold' | 'diamond' {
  if (item.achievement_type === 'night_owl') return 'gold';
  if (item.achievement_type === 'solo_focus') {
    const count = item.count ?? 1;
    return count >= 20 ? 'gold' : count >= 5 ? 'silver' : 'bronze';
  }
  if (item.achievement_type === 'promise_keeper') {
    const days = metadataNumber(item, 'stage_days', 1);
    return days >= 30
      ? 'diamond'
      : days >= 7
        ? 'gold'
        : days >= 3
          ? 'silver'
          : 'bronze';
  }
  if (item.achievement_type === 'together_streak') {
    const days = metadataNumber(item, 'days', 1);
    return days >= 7 ? 'gold' : days >= 3 ? 'silver' : 'bronze';
  }
  if (item.achievement_type === 'goal_milestone') {
    const count = metadataNumber(item, 'completed_goal_count', 1);
    return count >= 10 ? 'gold' : count >= 3 ? 'silver' : 'bronze';
  }
  if (item.achievement_type === 'focus_milestone') {
    const minutes = metadataNumber(item, 'threshold_minutes', 0);
    return minutes >= 6000 ? 'gold' : minutes >= 3000 ? 'silver' : 'bronze';
  }
  return item.tier ?? 'bronze';
}

export function achievementTitle(item: Achievement) {
  const type = item.achievement_type;
  if (type === 'night_owl') return '挑灯夜战';
  if (type === 'solo_focus') {
    const count = item.count ?? 1;
    return count >= 20 ? '独木成林' : count >= 5 ? '独行者' : '孤军奋战';
  }
  if (type === 'together_streak') {
    const days = metadataNumber(item, 'days', 1);
    return `${days >= 7 ? 7 : days >= 3 ? 3 : 1} 日相伴`;
  }
  if (type === 'goal_milestone') {
    const count = metadataNumber(item, 'completed_goal_count', 1);
    return `完成 ${count >= 10 ? 10 : count >= 3 ? 3 : 1} 个共同目标`;
  }
  if (type === 'focus_milestone') {
    const minutes = metadataNumber(item, 'threshold_minutes', 0);
    const hours = minutes >= 6000 ? 100 : minutes >= 3000 ? 50 : 10;
    return `累计专注 ${hours} 小时`;
  }
  return (
    (
      {
        dawn_walker: '破晓而行',
        unbroken_focus: '一气呵成',
        double_focus: '梅开二度',
        triple_focus: '三顾书桌',
        three_categories: '六边形战士',
        promise_keeper:
          metadataNumber(item, 'stage_days', 1) >= 30
            ? '久久为功'
            : metadataNumber(item, 'stage_days', 1) >= 7
              ? '滴水穿石'
              : metadataNumber(item, 'stage_days', 1) >= 3
                ? '初守约定'
                : '言出必行',
        return_after_break: '久别重逢',
        chance_encounter: '不期而遇',
        fellow_travelers:
          metadataNumber(item, 'stage', 3) >= 5 ? '万家灯火' : '三人成行',
        focus_relay: '接力燃灯',
        living_flame: '星火相传',
      } as Record<string, string>
    )[type] ?? '共同的光'
  );
}

export function achievementCondition(item: Achievement) {
  if (item.achievement_type === 'night_owl') {
    return '本地时间 23:00—23:59 开始，跨越午夜，并累计至少 60 分钟有效专注；暂停时间不计入。';
  }
  if (item.achievement_type === 'solo_focus') {
    return '单次会话累计至少 60 分钟有效专注，且有效专注片段不与同一空间其他成员重叠。';
  }
  if (item.achievement_type === 'together_streak') {
    const days = metadataNumber(item, 'days', 1);
    return `空间内至少两名有效成员全部完成空间签到目标，连续达成 ${days >= 7 ? 7 : days >= 3 ? 3 : 1} 天。`;
  }
  if (item.achievement_type === 'goal_milestone') {
    const count = metadataNumber(item, 'completed_goal_count', 1);
    return `空间累计完成 ${count >= 10 ? 10 : count >= 3 ? 3 : 1} 个经成员投票通过的共同目标。`;
  }
  if (item.achievement_type === 'focus_milestone') {
    const minutes = metadataNumber(item, 'threshold_minutes', 0);
    return `空间累计有效专注达到 ${minutes >= 6000 ? 100 : minutes >= 3000 ? 50 : 10} 小时。`;
  }
  return (
    (
      {
        dawn_walker: '本地时间 05:00—06:59 开始，并累计至少 60 分钟有效专注。',
        unbroken_focus: '整个会话从未暂停，并连续完成至少 60 分钟有效专注。',
        double_focus:
          '同一本地自然日完成 2 次专注，每次至少 30 分钟，且均未跨日。',
        triple_focus:
          '同一本地自然日完成 3 次专注，每次至少 30 分钟，且均未跨日。',
        three_categories:
          '同一本地自然日在 3 个不同最终任务类别中分别累计至少 30 分钟。',
        promise_keeper: '完成当天锁定的个人专注目标，连续达成后逐级解锁。',
        return_after_break:
          '连续 7 个完整本地自然日没有有效专注后，回归当天累计至少 60 分钟。',
        chance_encounter:
          '成员开始时间以相邻不超过 3 分钟形成一组，并共同连续专注至少 30 分钟。',
        fellow_travelers: '至少 3 人连续共同专注 30 分钟。',
        focus_relay:
          '一名成员完成至少 30 分钟后，另一名成员在 5 分钟内开始并完成至少 30 分钟；同一无向成员组合每天最多计数一次。',
        living_flame:
          '按空间时区计算：在完整的本地自然日内，至少两名合格成员参与；每名合格成员累计有效专注至少 30 分钟，且所有合格成员的有效专注片段并集须从当天 00:00 连续覆盖至次日 00:00，重叠部分只计算一次。',
      } as Record<string, string>
    )[item.achievement_type] ?? '完成对应的共同成就要求。'
  );
}

export function achievementSeries(item: Achievement) {
  return (
    {
      together_streak: '相伴系列',
      goal_milestone: '共同目标系列',
      focus_milestone: '时光里程碑',
      solo_focus: '独行者系列',
      promise_keeper: '守约者系列',
      fellow_travelers: '同行者系列',
    } as Record<string, string>
  )[item.achievement_type];
}

/**
 * Stages are derived from the current unlocked threshold, so future stages
 * are never rendered just because the series exists.
 */
export function achievementStages(item: Achievement) {
  const type = item.achievement_type;
  if (type === 'together_streak') {
    const days = metadataNumber(item, 'days', 1);
    return days >= 7
      ? '1 日相伴、3 日相伴、7 日相伴'
      : days >= 3
        ? '1 日相伴、3 日相伴'
        : '1 日相伴';
  }
  if (type === 'goal_milestone') {
    const count = metadataNumber(item, 'completed_goal_count', 1);
    return count >= 10
      ? '完成 1、3、10 个共同目标'
      : count >= 3
        ? '完成 1、3 个共同目标'
        : '完成 1 个共同目标';
  }
  if (type === 'focus_milestone') {
    const minutes = metadataNumber(item, 'threshold_minutes', 0);
    if (minutes < 600) return undefined;
    return minutes >= 6000
      ? '累计专注 10、50、100 小时'
      : minutes >= 3000
        ? '累计专注 10、50 小时'
        : '累计专注 10 小时';
  }
  if (type === 'solo_focus') {
    const count = item.count ?? 1;
    return count >= 20
      ? '孤军奋战、独行者、独木成林'
      : count >= 5
        ? '孤军奋战、独行者'
        : '孤军奋战';
  }
  if (type === 'promise_keeper') {
    const days = metadataNumber(item, 'stage_days', 1);
    return days >= 30
      ? '言出必行、初守约定、滴水穿石、久久为功'
      : days >= 7
        ? '言出必行、初守约定、滴水穿石'
        : days >= 3
          ? '言出必行、初守约定'
          : '言出必行';
  }
  if (type === 'fellow_travelers') {
    return metadataNumber(item, 'stage', 3) >= 5
      ? '三人成行、万家灯火'
      : '三人成行';
  }
  return undefined;
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
  if (item.achievement_type !== 'focus_milestone') return true;
  return metadataNumber(item, 'threshold_minutes', 0) >= 600;
}

const repeatableAchievementTypes = new Set([
  'solo_focus',
  'promise_keeper',
  'together_streak',
  'goal_milestone',
  'focus_milestone',
  'fellow_travelers',
  'living_flame',
]);

export function isRepeatableAchievement(item: Achievement) {
  return (
    item.repeatable ?? repeatableAchievementTypes.has(item.achievement_type)
  );
}

function isRepeatEvent(event: AchievementEvent) {
  if (event.notification_eligible === false) return true;
  if (event.notification_eligible === true) return false;
  if (event.is_unlock === false || event.is_repeat_event === true) return true;
  if (event.is_event === true && event.is_unlock !== true) return true;
  const kind = event.event_kind ?? event.event_type ?? event.kind;
  return kind === 'event' || kind === 'repeat' || kind === 'repeat_event';
}

export function visibleAchievementEvents(item: Achievement) {
  return item.events?.filter((event) => !isRepeatEvent(event)) ?? [];
}
