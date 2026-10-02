import type { QueryClient } from '@tanstack/react-query';

const pending = new WeakMap<QueryClient, Map<string, Set<string>>>();

/** Coalesce heartbeat responses and related realtime events into one refresh. */
export function scheduleRoomRefresh(
  client: QueryClient,
  spaceId: string,
  keys: readonly string[],
) {
  let rooms = pending.get(client);
  if (!rooms) {
    rooms = new Map();
    pending.set(client, rooms);
  }
  const queued = rooms.get(spaceId);
  if (queued) {
    keys.forEach((key) => queued.add(key));
    return;
  }
  const batch = new Set(keys);
  rooms.set(spaceId, batch);
  // A fixed window also flushes during a continuous stream of events.
  window.setTimeout(() => {
    rooms.delete(spaceId);
    batch.forEach((key) => {
      void client.invalidateQueries({ queryKey: [key, spaceId] });
    });
  }, 100);
}
