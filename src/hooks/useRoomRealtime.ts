import { useQueryClient } from '@tanstack/react-query';
import { REALTIME_SUBSCRIBE_STATES } from '@supabase/supabase-js';
import { useEffect, useState } from 'react';
import { getSupabaseClient } from '../lib/supabase';
import { loadMembership } from '../lib/membership';
import { useOnlineStatus } from './useOnlineStatus';

export type ConnectionState =
  | 'connected'
  | 'realtime_degraded'
  | 'unconfirmed'
  | 'offline'
  | 'reconnecting'
  | 'conflict';

export function useRoomRealtime(
  spaceId: string,
  snapshotUpdatedAt: number,
  requestFailed = false,
) {
  const queryClient = useQueryClient();
  const online = useOnlineStatus();
  const [channelState, setChannelState] =
    useState<Exclude<ConnectionState, 'offline' | 'reconnecting' | 'conflict'>>(
      'unconfirmed',
    );
  const [reconnectSince, setReconnectSince] = useState(() => Date.now());
  const [subscriptionEpoch, setSubscriptionEpoch] = useState(0);

  useEffect(() => {
    const supabase = getSupabaseClient();
    const refresh = () => {
      void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
      void queryClient.invalidateQueries({ queryKey: ['goals', spaceId] });
      void queryClient.invalidateQueries({
        queryKey: ['achievements', spaceId],
      });
      void queryClient.invalidateQueries({
        queryKey: ['personal-achievements', spaceId],
      });
      void queryClient.invalidateQueries({
        queryKey: ['nav-notifications', spaceId],
      });
      void queryClient.invalidateQueries({ queryKey: ['settings', spaceId] });
    };
    const refreshMembership = async () => {
      const state = await queryClient.fetchQuery({
        queryKey: ['membership'],
        queryFn: loadMembership,
        staleTime: 0,
      });
      if (state?.membership?.space_id === spaceId) return;
      queryClient.removeQueries({
        predicate: ({ queryKey }) => queryKey[1] === spaceId,
      });
    };
    const channel = supabase
      .channel(`space:${spaceId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'focus_sessions',
          filter: `space_id=eq.${spaceId}`,
        },
        refresh,
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'space_members',
          filter: `space_id=eq.${spaceId}`,
        },
        () => {
          refresh();
          void refreshMembership().catch(() => undefined);
        },
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'goals',
          filter: `space_id=eq.${spaceId}`,
        },
        refresh,
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'achievements',
          filter: `space_id=eq.${spaceId}`,
        },
        refresh,
      )
      .subscribe((status) => {
        if (status === REALTIME_SUBSCRIBE_STATES.SUBSCRIBED) {
          setChannelState('connected');
          refresh();
        } else if (
          status === REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR ||
          status === REALTIME_SUBSCRIBE_STATES.TIMED_OUT
        ) {
          setChannelState('realtime_degraded');
        } else if (status === REALTIME_SUBSCRIBE_STATES.CLOSED) {
          setChannelState('unconfirmed');
        }
      });

    const reconnect = () => {
      setReconnectSince(Date.now());
      refresh();
      setSubscriptionEpoch((value) => value + 1);
    };
    const visible = () => {
      if (document.visibilityState === 'visible') {
        reconnect();
      } else setChannelState('unconfirmed');
    };
    window.addEventListener('online', reconnect);
    document.addEventListener('visibilitychange', visible);
    return () => {
      window.removeEventListener('online', reconnect);
      document.removeEventListener('visibilitychange', visible);
      void supabase.removeChannel(channel);
    };
  }, [queryClient, spaceId, subscriptionEpoch]);

  if (!online) return requestFailed ? 'offline' : 'unconfirmed';
  if (reconnectSince > 0 && snapshotUpdatedAt < reconnectSince)
    return 'reconnecting';
  return channelState;
}
