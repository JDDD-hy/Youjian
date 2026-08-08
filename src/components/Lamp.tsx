import idleLamp from '../assets/lamp-idle-fixed.svg';
import focusingLamp from '../assets/lamp-focusing-fixed.svg';
import pausedLamp from '../assets/lamp-paused-fixed.svg';

const lampSources = {
  idle: idleLamp,
  focusing: focusingLamp,
  paused: pausedLamp,
} as const;

export function Lamp({
  state = 'idle',
  compact = false,
}: {
  state?: 'idle' | 'focusing' | 'paused';
  compact?: boolean;
}) {
  const src = lampSources[state];

  return (
    <img
      className={`lamp lamp--${state}${compact ? ' lamp--compact' : ''}`}
      src={src}
      alt=""
      aria-hidden="true"
    />
  );
}
