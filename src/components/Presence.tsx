import {
  Children,
  cloneElement,
  isValidElement,
  type HTMLAttributes,
  type AnimationEvent,
  type PropsWithChildren,
  type ReactElement,
  useEffect,
  useCallback,
  useState,
  useSyncExternalStore,
} from 'react';
import { PresenceContext, usePresence } from '../hooks/usePresence';
import '../styles/motion.css';

const motionQuery = '(prefers-reduced-motion: no-preference)';
const canAnimate = () => window.matchMedia?.(motionQuery).matches ?? false;
function subscribeMotion(notify: () => void) {
  const query = window.matchMedia?.(motionQuery);
  query?.addEventListener('change', notify);
  return () => query?.removeEventListener('change', notify);
}

type Item = { element: ReactElement; present: boolean };

function PresenceItem({
  element,
  present,
  onExit,
}: Item & { onExit: (key: ReactElement['key']) => void }) {
  const visible = usePresence() && present;
  useEffect(() => {
    if (present) return;
    // Also clean up when a tab is hidden or an animation is cancelled.
    const timer = window.setTimeout(() => onExit(element.key), 220);
    return () => window.clearTimeout(timer);
  }, [present, onExit, element.key]);

  const native = typeof element.type === 'string';
  const original = native ? (element.props as HTMLAttributes<HTMLElement>) : {};
  const motionProps = {
    'data-presence': visible ? 'present' : 'exiting',
    ...(!visible && { inert: true, 'aria-hidden': true as const }),
    onAnimationEnd: (event: AnimationEvent<HTMLElement>) => {
      original.onAnimationEnd?.(event);
      const root = native
        ? event.target === event.currentTarget
        : event.target instanceof HTMLElement &&
          event.target.parentElement === event.currentTarget;
      if (root && event.animationName === 'presence-out') onExit(element.key);
    },
  };

  return (
    <PresenceContext value={visible}>
      {native ? (
        cloneElement(
          element as ReactElement<HTMLAttributes<HTMLElement>>,
          motionProps,
        )
      ) : (
        <div className="presence-item" {...motionProps}>
          {element}
        </div>
      )}
    </PresenceContext>
  );
}

/** Keep keyed, presentational children mounted just long enough to leave. */
export function Presence({ children }: PropsWithChildren) {
  const animate = useSyncExternalStore(
    subscribeMotion,
    canAnimate,
    () => false,
  );
  const current = Children.toArray(children).filter(isValidElement);
  const [state, setState] = useState(() => ({
    children,
    animate,
    items: current.map((element) => ({ element, present: true })),
  }));

  const remove = useCallback((key: ReactElement['key']) => {
    setState((previous) => ({
      ...previous,
      items: previous.items.filter(
        (entry) => entry.present || entry.element.key !== key,
      ),
    }));
  }, []);

  if (state.children !== children || state.animate !== animate) {
    const items: Item[] = current.map((element) => ({
      element,
      present: true,
    }));
    const keys = new Set(current.map((element) => element.key));
    state.items.forEach((item, index) => {
      if (animate && !keys.has(item.element.key)) {
        items.splice(index, 0, { ...item, present: false });
      }
    });
    setState({ children, animate, items });
  }

  return state.items
    .filter((item) => animate || item.present)
    .map((item) => (
      <PresenceItem key={item.element.key} {...item} onExit={remove} />
    ));
}
