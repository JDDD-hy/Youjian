import { type FormEvent, useMemo, useState } from 'react';
import { localDateValue } from '../../domain/deadlineDate';
import type {
  PersonalDeadline,
  SetPersonalDeadlineInput,
} from '../../hooks/usePersonalDeadline';
import { AccessibleModal } from '../AccessibleModal';

export function DeadlineEditorModal({
  deadline,
  pending,
  onSave,
  onClose,
}: {
  deadline: PersonalDeadline | null;
  pending: boolean;
  onSave: (input: SetPersonalDeadlineInput) => Promise<unknown>;
  onClose: () => void;
}) {
  const initialTitle = deadline?.title ?? '';
  const initialDate = deadline?.target_date ?? '';
  const [title, setTitle] = useState(initialTitle);
  const [targetDate, setTargetDate] = useState(initialDate);
  const [saveError, setSaveError] = useState<string | null>(null);
  const today = useMemo(() => localDateValue(), []);
  const trimmedTitle = title.trim();
  const titleLength = Array.from(trimmedTitle).length;
  const dirty = title !== initialTitle || targetDate !== initialDate;
  const titleError =
    titleLength > 40
      ? '标题最多 40 个字。'
      : title.length > 0 && titleLength === 0
        ? '请写下倒数日名称。'
        : null;
  const dateError =
    targetDate && targetDate < today ? '日期不能早于今天。' : null;
  const valid = titleLength >= 1 && titleLength <= 40 && targetDate >= today;

  const requestClose = () => {
    if (pending) return;
    if (dirty && !window.confirm('放弃修改？')) return;
    onClose();
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || pending) return;
    setSaveError(null);
    try {
      await onSave({ title: trimmedTitle, targetDate });
      onClose();
    } catch (error) {
      setSaveError(
        error instanceof Error ? error.message : '暂时无法保存，请稍后重试。',
      );
    }
  };

  return (
    <AccessibleModal
      titleId="deadline-editor-title"
      kind="dialog"
      onClose={requestClose}
    >
      <form
        className="deadline-editor"
        onSubmit={(event) => void submit(event)}
      >
        <header className="deadline-editor__header">
          <div>
            <span className="deadline-editor__eyebrow">个人倒数日</span>
            <h2 id="deadline-editor-title">
              {deadline ? '修改 Deadline' : '写下你的 Deadline'}
            </h2>
          </div>
          <button
            type="button"
            className="deadline-editor__close"
            onClick={requestClose}
            aria-label="关闭"
            disabled={pending}
          >
            ×
          </button>
        </header>
        <label
          className="deadline-editor__field"
          htmlFor="deadline-title-input"
        >
          <span>目标</span>
          <input
            id="deadline-title-input"
            data-autofocus
            type="text"
            value={title}
            maxLength={80}
            placeholder="例如：你的Deadline"
            aria-invalid={Boolean(titleError)}
            aria-describedby={titleError ? 'deadline-title-error' : undefined}
            onChange={(event) => setTitle(event.target.value)}
          />
          <small className="deadline-editor__counter">{titleLength}/40</small>
          {titleError && (
            <small id="deadline-title-error" className="deadline-editor__error">
              {titleError}
            </small>
          )}
        </label>
        <label className="deadline-editor__field" htmlFor="deadline-date-input">
          <span>日期</span>
          <input
            id="deadline-date-input"
            type="date"
            aria-label="日期"
            className={
              targetDate ? undefined : 'deadline-editor__date-input--empty'
            }
            value={targetDate}
            min={today}
            aria-invalid={Boolean(dateError)}
            aria-describedby={dateError ? 'deadline-date-error' : undefined}
            onChange={(event) => setTargetDate(event.target.value)}
          />
          {!targetDate && (
            <span
              className="deadline-editor__date-placeholder"
              aria-hidden="true"
            >
              yyyy/mm/dd
            </span>
          )}
          {dateError && (
            <small id="deadline-date-error" className="deadline-editor__error">
              {dateError}
            </small>
          )}
        </label>
        <p className="deadline-editor__hint">
          可随时修改；按 Esc 或点击空白处退出，未保存的更改不会生效。
        </p>
        {saveError && (
          <p className="deadline-editor__error" role="alert">
            {saveError}
          </p>
        )}
        <footer className="deadline-editor__actions">
          <button
            type="button"
            className="secondary"
            onClick={requestClose}
            disabled={pending}
          >
            取消
          </button>
          <button
            type="submit"
            className="primary"
            disabled={!valid || pending}
          >
            {pending ? '保存中…' : '保存倒数日'}
          </button>
        </footer>
      </form>
    </AccessibleModal>
  );
}
