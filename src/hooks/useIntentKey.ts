import { useCallback, useRef } from 'react';
import { createIdempotencyKey } from '../lib/api';

export function useIntentKey() {
  const current = useRef<{ signature: string; key: string } | undefined>(
    undefined,
  );
  const get = useCallback((signature: string) => {
    if (current.current?.signature !== signature)
      current.current = { signature, key: createIdempotencyKey() };
    return current.current.key;
  }, []);
  const clear = useCallback(() => {
    current.current = undefined;
  }, []);
  return { get, clear };
}
