import { useEffect, useRef } from 'react';

export function useAutoAcknowledge(
  id: string | undefined,
  acknowledge: (id: string) => void,
) {
  const acknowledged = useRef(new Set<string>());
  useEffect(() => {
    if (!id || acknowledged.current.has(id)) return;
    acknowledged.current.add(id);
    acknowledge(id);
  }, [acknowledge, id]);
}
