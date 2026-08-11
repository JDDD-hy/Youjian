import type { FocusSession } from '../domain/types';
import { AccessibleModal } from './AccessibleModal';
import { appPath } from '../lib/appBase';

export function FocusHealthCheckModal({
  session,
  remainingSeconds,
  pending,
  error,
  onEnd,
  onContinue,
}: {
  session: FocusSession;
  remainingSeconds: number;
  pending: boolean;
  error?: string;
  onEnd: () => void;
  onContinue: () => void;
}) {
  return (
    <AccessibleModal
      kind="dialog"
      titleId="focus-health-title"
      onClose={() => undefined}
      closeOnBackdrop={false}
      closeOnEscape={false}
    >
      <div className="focus-health-check">
        <img src={appPath('lamp-dimmed.svg')} alt="" width="150" height="134" />
        <h2 id="focus-health-title">时间走过了两个小时</h2>
        <p>这一段专注已经足够漫长。</p>
        <p>先让目光离开屏幕，也让思绪有片刻留白。</p>
        <output className="focus-health-check__countdown" aria-live="polite">
          {remainingSeconds}
          <small>秒后自动结束</small>
        </output>
        <p className="sr-only">当前任务：{session.task_name}</p>
        {error && (
          <p className="field-error" role="alert">
            {error}
          </p>
        )}
        <div className="dialog__actions">
          <button
            className="button button--secondary"
            disabled={pending || remainingSeconds <= 0}
            onClick={onContinue}
          >
            我想继续专注
          </button>
          <button
            data-autofocus
            className="button button--primary"
            disabled={pending || remainingSeconds <= 0}
            onClick={onEnd}
          >
            收起此刻
          </button>
        </div>
      </div>
    </AccessibleModal>
  );
}
