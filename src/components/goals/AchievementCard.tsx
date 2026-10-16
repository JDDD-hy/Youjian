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
        {achievementSeries(item) && (
          <span className="achievement-card__series">
            {achievementSeries(item)}
          </span>
        )}
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
              <span
                className={`achievement-card__icon achievement-card__icon--${tier}`}
              >
                <AchievementIcon item={item} />
              </span>
              <h3 id={titleId}>{achievementTitle(item)}</h3>
              {achievementSeries(item) && (
                <small className="achievement-card__series">
                  系列 · {achievementSeries(item)}
                </small>
              )}
              {achievementStages(item) && (
                <small className="achievement-card__earned-stages">
                  已获得：{achievementStages(item)}
                </small>
              )}
              <p>{formatLocalDateTime(achievementDisplayDate(item))}</p>
              <button
                type="button"
                className="achievement-condition"
                aria-label={`达成条件：${achievementCondition(item)}`}
              >
                达成条件
                <span role="tooltip">{achievementCondition(item)}</span>
              </button>
              {!isPersonalAchievementType(item.achievement_type) && (
                <p className="achievement-profile__participants">
                  共同达成（{participantCount || '—'} 人）
                  <br />
                  {participantText}
                </p>
              )}
            </article>
          </AccessibleModal>
        )}
      </Presence>
    </>
  );
}
