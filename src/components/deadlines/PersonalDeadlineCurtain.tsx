import { useState } from 'react';
import { createPortal } from 'react-dom';
import { usePersonalDeadline } from '../../hooks/usePersonalDeadline';
import { DeadlineCurtain } from './DeadlineCurtain';
import { DeadlineEditorModal } from './DeadlineEditorModal';

/** Owns deadline data and interaction so route components only mount one overlay. */
export function PersonalDeadlineCurtain() {
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const deadline = usePersonalDeadline();

  return (
    <>
      <DeadlineCurtain
        open={open}
        onOpenChange={setOpen}
        deadline={deadline.deadline}
        dayState={deadline.dayState}
        loading={deadline.isLoading}
        error={deadline.isError}
        onRetry={() => void deadline.retry()}
        onEdit={() => {
          deadline.resetSaveError();
          setEditing(true);
        }}
      />
      {editing &&
        createPortal(
          <DeadlineEditorModal
            deadline={deadline.deadline}
            pending={deadline.isSaving}
            onSave={deadline.save}
            onClose={() => setEditing(false)}
          />,
          document.body,
        )}
    </>
  );
}
