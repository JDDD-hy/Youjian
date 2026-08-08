import { QueryClient } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  cacheActiveMembership,
  loadMembership,
  readCachedMembership,
} from './membership';

const getSession = vi.hoisted(() => vi.fn());
vi.mock('./supabase', () => ({
  getSupabaseClient: () => ({ auth: { getSession } }),
}));
vi.mock('./deviceIdentity', () => ({ clearDeviceIdentity: vi.fn() }));

describe('cacheActiveMembership', () => {
  beforeEach(() => {
    localStorage.clear();
    getSession.mockReset();
  });
  it('replaces a cached empty identity after create or join', () => {
    const client = new QueryClient();
    client.setQueryData(['membership'], null);
    const membership = {
      member_id: 'member',
      space_id: 'space',
      display_name: '小友',
      role: 'owner' as const,
      status: 'active' as const,
    };
    cacheActiveMembership(client, membership);
    expect(client.getQueryData(['membership'])).toEqual({
      membership,
      latest_disabled_membership: null,
    });
    expect(readCachedMembership()).toEqual({
      membership,
      latest_disabled_membership: null,
    });
  });

  it('discards malformed persisted membership state', () => {
    localStorage.setItem('youjian:membership', '{broken');
    expect(readCachedMembership()).toBeUndefined();
    expect(localStorage.getItem('youjian:membership')).toBeNull();
  });

  it('preserves the recovery clue when the auth session is missing', async () => {
    const client = new QueryClient();
    const membership = {
      member_id: 'member',
      space_id: 'space',
      display_name: 'Claudia',
      role: 'member' as const,
      status: 'active' as const,
    };
    cacheActiveMembership(client, membership);
    getSession.mockResolvedValue({ data: { session: null }, error: null });

    await expect(loadMembership()).resolves.toBeNull();
    expect(readCachedMembership()?.membership).toEqual(membership);
  });
});
