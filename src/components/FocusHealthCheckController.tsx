import { useCallback, useEffect, useRef, useState } from 'react';
import type { FocusSession } from '../domain/types';
import { ApiError, createIdempotencyKey, rpc } from '../lib/api';
import {
  closeFocusHealthNotification,
  showFocusHealthNotification,
  showFocusHealthResultNotification,
} from '../lib/focusHealth';
import { FocusHealthCheckModal } from './FocusHealthCheckModal';
import { FocusHealthResultModal } from './FocusHealthResultModal';

type HealthChoice = 'end' | 'continue';

export function FocusHealthCheckController({
  session,
  now,
  onSessionUpdate,
  onReconcile,
}: {
  session: FocusSession;
  now: number;
  onSessionUpdate: (session: FocusSession) => void;
  onReconcile: () => void;
}) {
  const [pendingChoice, setPendingChoice] = useState(false);
  const [error, setError] = useState<string>();
  const [dismissedResult, setDismissedResult] = useState(false);
  const notifiedTrigger = useRef<string | undefined>(undefined);
  const reconciledDeadline = useRef<string | undefined>(undefined);
  const health = session.health_check;
  const deadline = health?.deadline_at ? Date.parse(health.deadline_at) : NaN;
  const remainingSeconds = Number.isFinite(deadline)
    ? Math.max(0, Math.ceil((deadline - now) / 1000))
    : 0;
  const isPending =
    health?.state === 'pending' &&
    session.status === 'focusing' &&
    Boolean(health.deadline_at);
  const hasUnreadResult =
    !dismissedResult &&
    !health?.result_seen &&
    (session.completion_reason === 'health_check_accepted' ||
      session.completion_reason === 'health_check_timeout');

  const respond = useCallback(
    async (choice: HealthChoice) => {
      if (pendingChoice) return;
      setPendingChoice(true);
      setError(undefined);
      try {
        const { data } = await rpc<{ session: FocusSession }>(
          'respond_focus_health_check',
          {
            session_id: session.session_id,
            choice,
            idempotency_key: createIdempotencyKey(),
          },
        );
        onSessionUpdate(data.session);
        await showFocusHealthResultNotification(
          data.session,
          choice === 'continue',
        );
      } catch (caught) {
        if (caught instanceof ApiError && caught.authoritativeState) {
          onSessionUpdate(caught.authoritativeState as FocusSession);
        }
        setError(
          caught instanceof Error ? caught.message : '操作尚未生效，请重试。',
        );
        onReconcile();
      } finally {
        setPendingChoice(false);
      }
    },
    [onReconcile, onSessionUpdate, pendingChoice, session.session_id],
  );

  useEffect(() => {
    if (!isPending || !health?.triggered_at) return;
    if (notifiedTrigger.current === health.triggered_at) return;
    notifiedTrigger.current = health.triggered_at;
    if (document.visibilityState === 'visible') return;
    void showFocusHealthNotification(session).then((shown) => {
      void rpc('report_focus_health_notification', {
        session_id: session.session_id,
        shown,
      }).catch(() => undefined);
    });
  }, [health?.triggered_at, isPending, session]);

  useEffect(() => {
    if (!isPending || remainingSeconds > 0 || !health?.deadline_at) return;
    if (reconciledDeadline.current === health.deadline_at) return;
    reconciledDeadline.current = health.deadline_at;
    onReconcile();
  }, [health?.deadline_at, isPending, onReconcile, remainingSeconds]);

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      const data = event.data as {
        type?: string;
        action?: HealthChoice;
        sessionId?: string;
      };
      if (
        data.type === 'focus-health-action' &&
        data.sessionId === session.session_id &&
        (data.action === 'end' || data.action === 'continue')
      ) {
        void respond(data.action);
      }
    };
    navigator.serviceWorker?.addEventListener('message', handleMessage);
    return () =>
      navigator.serviceWorker?.removeEventListener('message', handleMessage);
  }, [respond, session.session_id]);

  useEffect(() => {
    const url = new URL(window.location.href);
    const action = url.searchParams.get('focusHealthAction');
    const sessionId = url.searchParams.get('focusHealthSession');
    if (
      sessionId === session.session_id &&
      (action === 'end' || action === 'continue')
    ) {
      url.searchParams.delete('focusHealthAction');
      url.searchParams.delete('focusHealthSession');
      window.history.replaceState({}, '', url);
      window.setTimeout(() => void respond(action), 0);
    }
  }, [respond, session.session_id]);

  const dismissResult = () => {
    setDismissedResult(true);
    void closeFocusHealthNotification();
    void rpc('mark_focus_health_result_seen', {
      session_id: session.session_id,
    }).finally(onReconcile);
  };

  return (
    <>
      {isPending && document.visibilityState === 'visible' && (
        <FocusHealthCheckModal
          session={session}
          remainingSeconds={remainingSeconds}
          pending={pendingChoice}
          error={error}
          onEnd={() => void respond('end')}
          onContinue={() => void respond('continue')}
        />
      )}
      {hasUnreadResult && (
        <FocusHealthResultModal session={session} onDismiss={dismissResult} />
      )}
    </>
  );
}
