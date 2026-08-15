import type { DeadlineDayState } from '../../domain/deadlineDate';
import { formatDeadlineDate } from '../../domain/deadlineDate';
import type { PersonalDeadline } from '../../hooks/usePersonalDeadline';

export interface DeadlineCurtainProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  deadline: PersonalDeadline | null;
  dayState: DeadlineDayState | null;
  loading?: boolean;
  error?: boolean;
  onRetry?: () => void;
  onEdit: () => void;
}

export function DeadlineCurtain({
  open,
  onOpenChange,
  deadline,
  dayState,
  loading = false,
  error = false,
  onRetry,
  onEdit,
}: DeadlineCurtainProps) {
  const contentId = 'personal-deadline-curtain';
  return (
    <div className={`deadline-curtain${open ? ' is-open' : ''}`}>
      <div className="deadline-curtain__roller" aria-hidden="true">
        <span className="deadline-curtain__roller-cap" />
        <span className="deadline-curtain__roller-bar" />
        <span className="deadline-curtain__roller-cap" />
      </div>
      <button
        type="button"
        className="deadline-curtain__cord"
        aria-expanded={open}
        aria-controls={contentId}
        aria-label={open ? '收起倒数日幕布' : '展开倒数日幕布'}
        onClick={() => onOpenChange(!open)}
      >
        <span className="deadline-curtain__cord-line" aria-hidden="true" />
        <span className="deadline-curtain__cord-ring" aria-hidden="true" />
      </button>
      <section
        id={contentId}
        className="deadline-curtain__sheet"
        aria-hidden={!open}
        inert={!open}
        aria-label="个人倒数日"
      >
        <div className="deadline-curtain__fabric">
          {loading ? (
            <div className="deadline-curtain__state" role="status">
              <span className="deadline-curtain__eyebrow">倒数日</span>
              <span className="deadline-curtain__loading">
                正在展开更远的目标…
              </span>
            </div>
          ) : error ? (
            <div className="deadline-curtain__state" role="alert">
              <span className="deadline-curtain__eyebrow">倒数日</span>
              <strong>暂时无法读取倒数日</strong>
              {onRetry && (
                <button
                  type="button"
                  className="deadline-curtain__text-button"
                  onClick={onRetry}
                >
                  重试
                </button>
              )}
            </div>
          ) : deadline && dayState && dayState.kind !== 'past' ? (
            <div className="deadline-curtain__content">
              <span className="deadline-curtain__eyebrow">倒数日</span>
              <button
                type="button"
                className="deadline-curtain__deadline"
                onClick={onEdit}
                aria-label={`修改倒数日：${deadline.title}`}
              >
                <span className="deadline-curtain__title">
                  {deadline.title}
                </span>
                <strong className="deadline-curtain__count">
                  {dayState.label}
                </strong>
                <time
                  className="deadline-curtain__date"
                  dateTime={deadline.target_date}
                >
                  {formatDeadlineDate(deadline.target_date)}
                </time>
              </button>
            </div>
          ) : (
            <div className="deadline-curtain__state">
              <span className="deadline-curtain__eyebrow">倒数日</span>
              <strong>设定一个更远的目标</strong>
              <button
                type="button"
                className="deadline-curtain__primary"
                onClick={onEdit}
              >
                设置倒数日
              </button>
            </div>
          )}
        </div>
        <div className="deadline-curtain__bottom-rail" aria-hidden="true" />
      </section>
    </div>
  );
}
