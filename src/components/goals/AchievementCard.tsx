import { useId, useState } from 'react';
import type { Achievement } from '../../domain/types';
import { AccessibleModal } from '../AccessibleModal';
import { Presence } from '../Presence';
import { AchievementIcon } from '../AchievementIcon';
import { formatLocalDateTime } from '../../lib/format';
import {
  achievementCondition,
  achievementDisplayDate,
  achievementSeries,
  achievementStages,
  achievementTitle,
  achievementTier,
  visibleAchievementEvents,
} from '../../domain/achievementTier';
import { uniqueAchievementParticipantCount } from '../../domain/achievementParticipants';
import { isPersonalAchievementType } from '../../domain/achievementCatalog';
import { AchievementCondition } from './AchievementCondition';

export function AchievementCard({ item }: { item: Achievement }) {
  const [open, setOpen] = useState(false);
  const titleId = useId();
  const tier = achievementTier(item);
  const participants = item.participants ?? [];
  const eventGroups = visibleAchievementEvents(item).filter(
    (event) => event.participants?.length,
  );
  const participantCount = uniqueAchievementParticipantCount({
    ...item,
    participants,
    events: eventGroups,
  });
  const participantText = eventGroups.length
    ? eventGroups
        .map(
          (event) =>
            `${formatLocalDateTime(event.earned_at)}：${event.participants!.map((participant) => participant.display_name).join('、')}`,
        )
        .join('\n')
    : item.participants_recorded
      ? participants
          .map((participant) =>
            participant.participation_days > 1
              ? `${participant.display_name}（${participant.participation_days} 天）`
              : participant.display_name,
          )
          .join('、')
      : '早期成就的参与成员记录暂缺';
  return (
    <>
      <button
        type="button"
        className={`achievement-card achievement-card--${tier}${!item.seen ? ' achievement--new' : ''}`}
        aria-label={`查看${achievementTitle(item)}资料卡`}
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        <span
          className={`achievement-card__icon achievement-card__icon--${tier}`}
        >
          <AchievementIcon item={item} />
        </span>
      </button>
      <Presence>
        {open && (
          <AccessibleModal
            titleId={titleId}
            kind="dialog"
            onClose={() => setOpen(false)}
          >
            <article
              className={`achievement-profile achievement-card achievement-card--${tier}`}
            >
              <button
                type="button"
                className="achievement-profile__close"
                aria-label="关闭成就资料卡"
                onClick={() => setOpen(false)}
              >
                ×
              </button>
              <header className="achievement-profile__hero">
                <span
                  className={`achievement-card__icon achievement-card__icon--${tier}`}
                >
                  <AchievementIcon item={item} />
                </span>
                <h3 id={titleId}>{achievementTitle(item)}</h3>
                {achievementSeries(item) && (
                  <small className="achievement-card__series">
                    {achievementSeries(item)}
                  </small>
                )}
              </header>
              <dl className="achievement-profile__details">
                <dt>获得时间</dt>
                <dd>{formatLocalDateTime(achievementDisplayDate(item))}</dd>
                {achievementStages(item) && (
                  <>
                    <dt>已达成</dt>
                    <dd className="achievement-card__earned-stages">
                      {achievementStages(item)}
                    </dd>
                  </>
                )}
                {!isPersonalAchievementType(item.achievement_type) && (
                  <>
                    <dt>共同达成</dt>
                    <dd className="achievement-profile__participants">
                      {participantText}（{participantCount || '—'} 人）
                    </dd>
                  </>
                )}
              </dl>
              <AchievementCondition text={achievementCondition(item)} />
            </article>
          </AccessibleModal>
        )}
      </Presence>
    </>
  );
}
