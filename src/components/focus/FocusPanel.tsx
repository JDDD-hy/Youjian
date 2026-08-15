import type { ReactNode } from 'react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import type { FocusSession, TaskRevision } from '../../domain/types';
import { calculateFocusSeconds } from '../../hooks/useServerClock';
import {
  categoryLabels,
  formatDuration,
  formatLocalDateTime,
} from '../../lib/format';
import type { ConnectionState } from '../../hooks/useRoomRealtime';
import { Icon } from '../Icons';
import { Lamp } from '../Lamp';

export function TaskHistory({ history }: { history: TaskRevision[] }) {
  const [expanded, setExpanded] = useState(false);
  if (!history.length) return null;
  return (
    <div className="task-history">
      <button
        className="task-history__toggle"
        type="button"
        aria-expanded={expanded}
        onClick={() => setExpanded((value) => !value)}
      >
        已修改 · {expanded ? '收起旧任务' : `查看旧任务 (${history.length})`}
      </button>
      {expanded && (
        <ol className="task-history__list">
          {history.map((revision, index) => (
            <li key={`${revision.changed_at}:${index}`}>
              <span>{revision.task_name}</span>
              <small>
                {categoryLabels[revision.category]} · 修改于{' '}
                {formatLocalDateTime(revision.changed_at)}
              </small>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function SettledNotice({
  session,
  onDismiss,
}: {
  session: FocusSession;
  onDismiss: () => void;
}) {
  const reason = session.completion_reason;
  const copy =
    reason === 'pause_timeout'
      ? '因暂停超过 15 分钟，本次已自动结束。'
      : reason === 'focus_limit'
        ? '本次已达到单次专注上限并自动结束。长时间专注后请适当休息。'
        : reason === 'health_check_accepted'
          ? '两小时专注后，你主动收起了这一盏灯。'
          : reason === 'health_check_timeout'
            ? '两小时健康检查未收到选择，本次已自动结束。'
            : session.status === 'discarded'
              ? '本次不足 5 分钟，记录已保留，但不会计入统计和打卡。'
              : '这一段专注已经完成。';
  return (
    <section className="result-card" aria-live="polite">
      <span className="result-card__icon">
        <Icon name={session.status === 'discarded' ? 'clock' : 'check'} />
      </span>
      <h2>{session.status === 'discarded' ? '这一小段已记录' : '专注完成'}</h2>
      <p>{copy}</p>
      <strong>{formatDuration(session.credited_focus_seconds ?? 0)}</strong>
      <button className="button button--primary" onClick={onDismiss}>
        再来一段
      </button>
      <Link className="button button--text" to="stats">
        查看记录
      </Link>
    </section>
  );
}

interface FocusPanelProps {
  session: FocusSession;
  now: number;
  connection: ConnectionState;
  onPause: () => void;
  onResume: () => void;
  onEnd: () => void;
  onEdit: () => void;
  onDismiss: () => void;
  pending: boolean;
  timezoneLabel?: string;
  lampOverlay?: ReactNode;
}

export function FocusPanel({
  session,
  now,
  connection,
  onPause,
  onResume,
  onEnd,
  onEdit,
  onDismiss,
  pending,
  timezoneLabel,
  lampOverlay,
}: FocusPanelProps) {
  const seconds = calculateFocusSeconds(session, now);
  if (session.status === 'completed' || session.status === 'discarded')
    return <SettledNotice session={session} onDismiss={onDismiss} />;
  const authorityPending =
    connection === 'reconnecting' || connection === 'conflict';
  if (session.status === 'paused') {
    const countdown = Math.max(
      0,
      Math.ceil((Date.parse(session.auto_settle_at ?? '') - now) / 1000),
    );
    return (
      <section className="focus-panel focus-panel--paused">
        <div className="pause-stage">
          <div className="focus-panel__lamp-zone">
            <Lamp state="paused" />
            {lampOverlay}
          </div>
          <div className="focus-panel__task-zone">
            <div className="focus-panel__status-line">
              <p className="eyebrow">暂时离开</p>
              {timezoneLabel && (
                <span className="focus-timezone-label">{timezoneLabel}</span>
              )}
            </div>
            <h2>{session.task_name}</h2>
            <p>{categoryLabels[session.category]}</p>
            <TaskHistory history={session.task_history ?? []} />
            <button
              className="button button--text task-edit-button"
              type="button"
              disabled={pending || authorityPending || countdown === 0}
              onClick={onEdit}
            >
              修改任务
            </button>
            <strong className="timer">{formatDuration(seconds, true)}</strong>
            <hr />
            <p
              className={
                countdown <= 60 ? 'countdown countdown--warning' : 'countdown'
              }
            >
              {countdown > 0
                ? `${String(Math.floor(countdown / 60)).padStart(2, '0')}:${String(countdown % 60).padStart(2, '0')} 后自动结束`
                : '正在等待服务器确认'}
            </p>
            <button
              className="button button--pause button--wide"
              disabled={pending || authorityPending || countdown === 0}
              onClick={onResume}
            >
              {pending ? '正在同步…' : '继续专注'}
            </button>
          </div>
        </div>
        <button
          className="button button--text"
          disabled={pending || authorityPending}
          onClick={onEnd}
        >
          结束本次
        </button>
      </section>
    );
  }
  return (
    <section className="focus-panel focus-panel--active">
      <div className="focus-panel__lamp-zone">
        <Lamp state="focusing" />
        {lampOverlay}
      </div>
      <div className="focus-panel__task-zone">
        <div className="focus-panel__status-line">
          <p className="eyebrow">灯已点亮</p>
          {timezoneLabel && (
            <span className="focus-timezone-label">{timezoneLabel}</span>
          )}
        </div>
        <h2>{session.task_name}</h2>
        <p>{categoryLabels[session.category]}</p>
        <TaskHistory history={session.task_history ?? []} />
        <button
          className="button button--text task-edit-button"
          type="button"
          disabled={pending || authorityPending}
          onClick={onEdit}
        >
          修改任务
        </button>
        <strong className="timer">{formatDuration(seconds, true)}</strong>
        {session.auto_settle_at &&
          Date.parse(session.auto_settle_at) - now <= 30 * 60 * 1000 && (
            <p className="limit-note">
              距离本次专注上限还有{' '}
              {formatDuration(
                (Date.parse(session.auto_settle_at) - now) / 1000,
              )}
            </p>
          )}
        <button
          className="button button--primary button--wide"
          disabled={pending || authorityPending}
          onClick={onPause}
        >
          {pending ? '正在暂停…' : '暂停'}
        </button>
        <button
          className="button button--text"
          disabled={pending || authorityPending}
          onClick={onEnd}
        >
          结束本次
        </button>
      </div>
    </section>
  );
}
