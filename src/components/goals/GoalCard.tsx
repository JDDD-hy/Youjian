import type { Goal } from '../../domain/types';
import {
  formatLocalDateTime,
  goalTypeLabels,
  periodLabels,
} from '../../lib/format';
import { Icon } from '../Icons';

export function GoalCard({ goal }: { goal: Goal }) {
  const credited = goal.progress.credited_value;
  const percent =
    credited === null
      ? null
      : Math.min(100, Math.round((credited / goal.target_value) * 100));
  const unit = goal.goal_type === 'shared_checkin_days' ? '天' : '分钟';
  const statusLabel =
    goal.status === 'scheduled'
      ? '即将生效'
      : goal.status === 'failed'
        ? '未达成'
        : goal.status === 'completed' || goal.progress.completed
          ? '已完成'
          : percent === null
            ? '按成员计算'
            : `${percent}%`;

  return (
    <article className={`goal-card goal-card--${goal.status}`}>
      <div className="goal-card__top">
        <span className="pill">{periodLabels[goal.period_type]}</span>
        <span>{statusLabel}</span>
      </div>
      <h3>{goalTypeLabels[goal.goal_type]}</h3>
      {credited === null ? (
        <p>
          每位成员每天至少完成 {goal.target_value} {unit}
        </p>
      ) : (
        <p>
          {credited} / {goal.target_value} {unit}
        </p>
      )}
      {percent !== null && (
        <progress
          className="progress-track"
          value={percent}
          max={100}
          aria-label={`目标完成进度 ${percent}%`}
        >
          {percent}%
        </progress>
      )}
      {goal.progress.members && (
        <div className="goal-members">
          {goal.progress.members.map((member) => (
            <div key={member.member_id}>
              <span>{member.display_name}</span>
              <span>
                {goal.goal_type === 'per_member_minutes' &&
                member.required_days !== undefined
                  ? `已达标 ${member.completed_days ?? 0} / ${member.required_days} 天 · 当天 ${member.current_day_credited_minutes ?? 0} / ${goal.target_value} 分钟`
                  : `${member.credited_value ?? 0} / ${goal.target_value} ${unit}`}{' '}
                {member.completed && <Icon name="check" />}
              </span>
            </div>
          ))}
        </div>
      )}
      <small>
        {formatLocalDateTime(goal.starts_at)} —{' '}
        {formatLocalDateTime(goal.ends_at)}
      </small>
    </article>
  );
}
