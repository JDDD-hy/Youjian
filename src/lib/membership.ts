import type { QueryClient } from '@tanstack/react-query';
import type { Membership } from '../domain/types';
import { isApiError, rpc, withRequestTimeout } from './api';
import { getSupabaseClient } from './supabase';
import { clearDeviceIdentity } from './deviceIdentity';

export interface MembershipState {
  membership: Membership | null;
  latest_disabled_membership: {
    space_name: string;
    display_name: string;
    disabled_at: string;
    end_reason?: 'disabled' | 'left' | 'dissolved';
  } | null;
}

const cachedMembershipKey = 'youjian:membership';
const sessionRecoveryErrorCodes = new Set(['AUTH_REQUIRED', 'TRANSPORT_ERROR']);

function persistMembership(state: MembershipState | null) {
  if (typeof window === 'undefined') return;
  if (!state?.membership) {
    localStorage.removeItem(cachedMembershipKey);
    return;
  }
  localStorage.setItem(cachedMembershipKey, JSON.stringify(state));
}

export function readCachedMembership(): MembershipState | undefined {
  if (typeof window === 'undefined') return undefined;
  try {
    const value = JSON.parse(
      localStorage.getItem(cachedMembershipKey) ?? 'null',
    ) as MembershipState | null;
    const membership = value?.membership;
    if (
      !membership ||
      membership.status !== 'active' ||
      typeof membership.member_id !== 'string' ||
      typeof membership.space_id !== 'string' ||
      typeof membership.display_name !== 'string' ||
      !['owner', 'member'].includes(membership.role)
    )
      return undefined;
    return value ?? undefined;
  } catch {
    localStorage.removeItem(cachedMembershipKey);
    return undefined;
  }
}

export async function loadMembership(): Promise<MembershipState | null> {
  const supabase = getSupabaseClient();
  const { data, error } = await withRequestTimeout(supabase.auth.getSession());
  if (error) throw error;
  if (!data.session) {
    return null;
  }
  let state: MembershipState;
  try {
    state = (await rpc<MembershipState>('get_my_membership')).data;
  } catch (firstError) {
    if (
      !isApiError(firstError) ||
      !sessionRecoveryErrorCodes.has(firstError.code)
    ) {
      throw firstError;
    }

    // A full navigation (for example, the contributors page logo) creates a
    // new Supabase client. If the first RPC races the persisted-session
    // refresh, retry once with a freshly rotated session before treating the
    // identity as invalid. Do not erase the device identity on this first
    // failure; doing so would turn a transient navigation race into data loss.
    const refreshed = await withRequestTimeout(supabase.auth.refreshSession());
    if (refreshed.error || !refreshed.data.session) {
      return null;
    }

    try {
      state = (await rpc<MembershipState>('get_my_membership')).data;
    } catch (secondError) {
      if (isApiError(secondError) && secondError.code === 'AUTH_REQUIRED') {
        await clearDeviceIdentity();
        return null;
      }
      throw secondError;
    }
  }
  persistMembership(state);
  return state;
}

export function cacheActiveMembership(
  queryClient: QueryClient,
  membership: Membership,
) {
  queryClient.setQueryData<MembershipState>(['membership'], {
    membership,
    latest_disabled_membership: null,
  });
  persistMembership({ membership, latest_disabled_membership: null });
}
