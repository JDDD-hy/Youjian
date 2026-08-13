import { QueryClient } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  cacheActiveMembership,
  loadMembership,
  readCachedMembership,
} from './membership';
import { ApiError } from './api';

const getSession = vi.hoisted(() => vi.fn());
const refreshSession = vi.hoisted(() => vi.fn());
const rpc = vi.hoisted(() => vi.fn());
const clearIdentity = vi.hoisted(() => vi.fn());
vi.mock('./supabase', () => ({
  getSupabaseClient: () => ({ auth: { getSession, refreshSession } }),
}));
vi.mock('./deviceIdentity', () => ({ clearDeviceIdentity: clearIdentity }));
vi.mock('./api', async () => {
  const actual = await vi.importActual<typeof import('./api')>('./api');
  return { ...actual, rpc };
});

describe('cacheActiveMembership', () => {
  beforeEach(() => {
    localStorage.clear();
    getSession.mockReset();
    refreshSession.mockReset();
    rpc.mockReset();
    clearIdentity.mockReset();
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

  it('refreshes once before clearing an identity after a navigation race', async () => {
    const membership = {
      member_id: 'member',
      space_id: 'space',
      display_name: 'Claudia',
      role: 'member' as const,
      status: 'active' as const,
    };
    const state = { membership, latest_disabled_membership: null };
    getSession.mockResolvedValue({
      data: { session: { id: 'stale' } },
      error: null,
    });
    refreshSession.mockResolvedValue({
      data: { session: { id: 'fresh' } },
      error: null,
    });
    rpc
      .mockRejectedValueOnce(new ApiError('AUTH_REQUIRED'))
      .mockResolvedValueOnce({ data: state });

    await expect(loadMembership()).resolves.toEqual(state);
    expect(refreshSession).toHaveBeenCalledOnce();
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(clearIdentity).not.toHaveBeenCalled();
  });

  it('keeps the recovery clue when a refresh cannot restore the session', async () => {
    const membership = {
      member_id: 'member',
      space_id: 'space',
      display_name: 'Claudia',
      role: 'member' as const,
      status: 'active' as const,
    };
    cacheActiveMembership(new QueryClient(), membership);
    getSession.mockResolvedValue({
      data: { session: { id: 'stale' } },
      error: null,
    });
    refreshSession.mockResolvedValue({ data: { session: null }, error: null });
    rpc.mockRejectedValueOnce(new ApiError('AUTH_REQUIRED'));

    await expect(loadMembership()).resolves.toBeNull();
    expect(clearIdentity).not.toHaveBeenCalled();
    expect(readCachedMembership()?.membership).toEqual(membership);
  });
});
