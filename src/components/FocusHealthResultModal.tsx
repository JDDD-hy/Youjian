import type { FocusSession } from '../domain/types';
import { formatDuration, formatLocalDateTime } from '../lib/format';
import { AccessibleModal } from './AccessibleModal';

export function FocusHealthResultModal({
  session,
  onDismiss,
}: {
  session: FocusSession;
  onDismiss: () => void;
}) {
  const automatic = session.completion_reason === 'health_check_timeout';
  return (
    <AccessibleModal
      kind="dialog"
      titleId="focus-health-result-title"
      onClose={onDismiss}
    >
      <h2 id="focus-health-result-title">
        {automatic ? '这一段专注，先停在这里' : '灯已收起'}
      </h2>
      <p>
        {automatic && session.completed_at
          ? `两个小时已经走过，专注已于 ${formatLocalDateTime(session.completed_at, session.timezone_snapshot)} 自动结束。`
          : '这次专注已按你的选择结束。'}
      </p>
      <p>
        本次共专注 {formatDuration(session.credited_focus_seconds ?? 0)}
        ，现在让自己休息一会儿吧。
      </p>
      <button
        data-autofocus
        className="button button--primary button--full"
        onClick={onDismiss}
      >
        知道了
      </button>
    </AccessibleModal>
  );
}
