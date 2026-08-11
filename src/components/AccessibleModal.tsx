import {
  type MouseEvent,
  type PropsWithChildren,
  useEffect,
  useRef,
  useState,
} from 'react';

const focusable =
  'button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

export function AccessibleModal({
  titleId,
  kind = 'drawer',
  onClose,
  closeOnBackdrop = true,
  closeOnEscape = true,
  children,
}: PropsWithChildren<{
  titleId: string;
  kind?: 'drawer' | 'dialog';
  onClose: () => void;
  closeOnBackdrop?: boolean;
  closeOnEscape?: boolean;
}>) {
  const panel = useRef<HTMLElement>(null);
  const [returnFocus] = useState(() =>
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null,
  );
  const closeRef = useRef(onClose);
  useEffect(() => {
    closeRef.current = onClose;
  }, [onClose]);
  useEffect(() => {
    const element = panel.current;
    const initial =
      element?.querySelector<HTMLElement>('[data-autofocus]') ??
      element?.querySelector<HTMLElement>(focusable);
    if (initial) initial.focus();
    else element?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        if (closeOnEscape) closeRef.current();
        return;
      }
      if (event.key !== 'Tab' || !element) return;
      const nodes = Array.from(
        element.querySelectorAll<HTMLElement>(focusable),
      ).filter((node) => !node.hidden);
      if (!nodes.length) {
        event.preventDefault();
        element.focus();
        return;
      }
      const first = nodes[0]!;
      const last = nodes[nodes.length - 1]!;
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', keydown);
    return () => {
      document.removeEventListener('keydown', keydown);
      returnFocus?.focus();
    };
  }, [closeOnEscape, returnFocus]);
  const backdrop = (event: MouseEvent<HTMLDivElement>) => {
    if (closeOnBackdrop && event.target === event.currentTarget) onClose();
  };
  return (
    <div className="modal-backdrop" onMouseDown={backdrop}>
      <section
        ref={panel}
        tabIndex={-1}
        className={kind}
        role={kind === 'dialog' ? 'alertdialog' : 'dialog'}
        aria-modal="true"
        aria-labelledby={titleId}
      >
        {children}
      </section>
    </div>
  );
}
