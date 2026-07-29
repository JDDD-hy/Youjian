import { QueryClient } from '@tanstack/react-query';
import { beforeEach, describe, expect, it } from 'vitest';
import { cacheActiveMembership, readCachedMembership } from './membership';

describe('cacheActiveMembership', () => {
  beforeEach(() => localStorage.clear());
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
});
