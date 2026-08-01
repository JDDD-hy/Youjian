export function Lamp({
  state = 'idle',
  compact = false,
}: {
  state?: 'idle' | 'focusing' | 'paused';
  compact?: boolean;
}) {
  const src = `${import.meta.env.BASE_URL}lamp-${state}.svg`;

  return (
    <img
      className={`lamp lamp--${state}${compact ? ' lamp--compact' : ''}`}
      src={src}
      alt=""
      aria-hidden="true"
    />
  );
}
