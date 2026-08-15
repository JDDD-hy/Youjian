import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  deadlineDayState,
  localDateValue,
  millisecondsUntilNextLocalDay,
} from '../domain/deadlineDate';
import { rpc } from '../lib/api';

export interface PersonalDeadline {
  id: string;
  title: string;
  target_date: string;
  created_at: string;
  updated_at: string;
}

interface DeadlineResponse {
  deadline: PersonalDeadline | null;
}

export interface SetPersonalDeadlineInput {
  title: string;
  targetDate: string;
}

export const personalDeadlineQueryKey = ['personal-deadline'] as const;

function deviceTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
}

export function usePersonalDeadline({ enabled = true } = {}) {
  const queryClient = useQueryClient();
  const [today, setToday] = useState(() => localDateValue());
  const query = useQuery({
    queryKey: personalDeadlineQueryKey,
    queryFn: async () =>
      (await rpc<DeadlineResponse>('get_personal_deadline')).data.deadline,
    enabled,
    staleTime: 60_000,
  });

  useEffect(() => {
    if (!enabled) return;
    let timeout: number | undefined;
    const schedule = () => {
      timeout = window.setTimeout(() => {
        setToday(localDateValue());
        schedule();
      }, millisecondsUntilNextLocalDay() + 50);
    };
    schedule();
    return () => window.clearTimeout(timeout);
  }, [enabled]);

  const mutation = useMutation({
    mutationFn: async ({ title, targetDate }: SetPersonalDeadlineInput) =>
      (
        await rpc<DeadlineResponse>('set_personal_deadline', {
          title: title.trim(),
          target_date: targetDate,
          timezone: deviceTimezone(),
        })
      ).data.deadline,
    onSuccess: (deadline) => {
      queryClient.setQueryData(personalDeadlineQueryKey, deadline);
    },
  });

  const deadline = query.data ?? null;
  const dayState = useMemo(
    () => (deadline ? deadlineDayState(deadline.target_date, today) : null),
    [deadline, today],
  );
  const visibleDeadline = dayState?.kind === 'past' ? null : deadline;

  return {
    deadline: visibleDeadline,
    dayState: visibleDeadline ? dayState : null,
    hasStoredDeadline: deadline !== null,
    isLoading: query.isLoading,
    isError: query.isError,
    error: query.error,
    retry: query.refetch,
    save: mutation.mutateAsync,
    isSaving: mutation.isPending,
    saveError: mutation.error,
    resetSaveError: mutation.reset,
  };
}
