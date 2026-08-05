import type { Achievement } from './types';

export function uniqueAchievementParticipantCount(item: Achievement) {
  const eventParticipants =
    item.events?.flatMap((event) => event.participants ?? []) ?? [];
  const participants = eventParticipants.length
    ? eventParticipants
    : (item.participants ?? []);

  return new Set(participants.map((participant) => participant.member_id)).size;
}
