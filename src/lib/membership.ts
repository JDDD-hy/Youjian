import type { QueryClient } from '@tanstack/react-query';
import type { Membership } from '../domain/types';
import { rpc, withRequestTimeout } from './api';
import { getSupabaseClient } from './supabase';

export interface MembershipState {
  membership: Membership | null;
  latest_disabled_membership: {
    space_name: string;
    display_name: string;
    disabled_at: string;
  } | null;
}

const cachedMembershipKey = 'youjian:membership';

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
  const { data, error } = await withRequestTimeout(
    getSupabaseClient().auth.getSession(),
  );
  if (error) throw error;
  if (!data.session) {
    persistMembership(null);
    return null;
  }
  const state = (await rpc<MembershipState>('get_my_membership')).data;
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
