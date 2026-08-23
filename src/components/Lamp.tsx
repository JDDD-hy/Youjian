import idleLamp from '../assets/lamp-idle-fixed.svg';
import focusingLamp from '../assets/lamp-focusing-fixed.svg';
import pausedLamp from '../assets/lamp-paused-fixed.svg';
import entertainmentFocusingLamp from '../assets/lamp-entertainment-focusing.svg';
import type { FocusCategory } from '../domain/types';
import { resolveLampVariant, type LampState } from '../domain/lampVariant';

const lampSources = {
  idle: idleLamp,
  focusing: focusingLamp,
  paused: pausedLamp,
  'entertainment-focusing': entertainmentFocusingLamp,
} as const;

export function Lamp({
  state = 'idle',
  category,
  compact = false,
}: {
  state?: LampState;
  category?: FocusCategory;
  compact?: boolean;
}) {
  const variant = resolveLampVariant(state, category);
  const src = lampSources[variant];

  return (
    <img
      className={`lamp lamp--${state}${compact ? ' lamp--compact' : ''}`}
      data-lamp-variant={variant}
      src={src}
      alt=""
      aria-hidden="true"
    />
  );
}
