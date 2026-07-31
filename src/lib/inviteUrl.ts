const inviteTokenPattern = /^[A-Za-z0-9_-]{40,128}$/;

export function inviteInputToUrl(
  value: string,
  origin = window.location.origin,
  basePath = import.meta.env.BASE_URL,
): string | null {
  const trimmed = value.trim();
  if (inviteTokenPattern.test(trimmed))
    return `${new URL(origin).origin}${normalizedBase(basePath)}invite/${trimmed}`;
  return normalizeInviteUrl(trimmed, origin, basePath);
}

export function normalizeInviteUrl(
  value: string | null | undefined,
  origin = window.location.origin,
  basePath = import.meta.env.BASE_URL,
): string | null {
  if (!value) return null;
  try {
    const parsed = new URL(value, origin);
    const parts = parsed.pathname.split('/').filter(Boolean);
    const baseParts = normalizedBase(basePath).split('/').filter(Boolean);
    // A deployment may move between a project sub-path and a root/custom
    // domain. The token is portable, so accept invite paths from either the
    // current base or a previous base and always re-home them to this app.
    const inviteIndex = parts.length - 2;
    const portable = inviteIndex >= 0 && parts[inviteIndex] === 'invite';
    const scoped =
      parts.length === baseParts.length + 2 &&
      baseParts.every((part, index) => parts[index] === part) &&
      parts.at(-2) === 'invite';
    if (!portable && !scoped) return null;
    const token = parts.at(-1);
    if (!token || !inviteTokenPattern.test(token)) return null;
    return `${new URL(origin).origin}${normalizedBase(basePath)}invite/${token}`;
  } catch {
    return null;
  }
}

function normalizedBase(value: string) {
  const trimmed = value.replace(/^\/+|\/+$/g, '');
  return trimmed ? `/${trimmed}/` : '/';
}
