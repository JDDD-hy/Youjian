const inviteTokenPattern = /^[A-Za-z0-9_-]{40,128}$/;

export function inviteInputToUrl(
  value: string,
  origin = window.location.origin,
): string | null {
  const trimmed = value.trim();
  if (inviteTokenPattern.test(trimmed))
    return `${new URL(origin).origin}/invite/${trimmed}`;
  return normalizeInviteUrl(trimmed, origin);
}

export function normalizeInviteUrl(
  value: string | null | undefined,
  origin = window.location.origin,
): string | null {
  if (!value) return null;
  try {
    const parsed = new URL(value, origin);
    const parts = parsed.pathname.split('/').filter(Boolean);
    if (parts.length !== 2 || parts[0] !== 'invite') return null;
    const token = parts[1];
    if (!token || !inviteTokenPattern.test(token)) return null;
    return `${new URL(origin).origin}/invite/${token}`;
  } catch {
    return null;
  }
}
