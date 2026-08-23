export type LampState = 'idle' | 'focusing' | 'paused';
export type LampVariant = LampState | 'entertainment-focusing';

export function resolveLampVariant(
  state: LampState,
  category?: string,
): LampVariant {
  if (state === 'focusing' && category === 'entertainment')
    return 'entertainment-focusing';
  return state;
}
