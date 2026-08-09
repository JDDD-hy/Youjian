export const STATS_QUERY_RETRY_COUNT = 4;

export function statsQueryRetryDelay(attemptIndex: number) {
  return Math.min(1_000 * 2 ** attemptIndex, 4_000);
}
