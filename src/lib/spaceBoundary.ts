import { ApiError } from './api';
import { reportSafeError } from './safeError';

export function assertRouteSpace(
  routeSpaceId: string,
  responseSpaceId: string,
  source: string,
) {
  if (routeSpaceId === responseSpaceId) return;
  const error = new ApiError('CROSS_SPACE_RESPONSE');
  reportSafeError(error, source);
  throw error;
}
