export function Lamp({
  state = 'idle',
  compact = false,
}: {
  state?: 'idle' | 'focusing' | 'paused';
  compact?: boolean;
}) {
  return (
    <div
      className={`lamp lamp--${state}${compact ? ' lamp--compact' : ''}`}
      aria-hidden="true"
    >
      <span className="lamp__aura" />
      <span className="lamp__neck" />
      <span className="lamp__shade" />
      <span className="lamp__light" />
      <span className="lamp__arm" />
      <span className="lamp__joint" />
      <span className="lamp__stem" />
      <span className="lamp__base" />
    </div>
  );
}
