export function canonicalAppPath(
  pathname: string,
  basePath = import.meta.env.BASE_URL,
): string | null {
  const baseParts = basePath.split('/').filter(Boolean);
  if (baseParts.length === 0) return null;

  const parts = pathname.split('/').filter(Boolean);
  const baseName = baseParts.at(-1)!;
  let lastBaseIndex = -1;
  for (let index = 0; index < parts.length; index += 1) {
    if (parts[index]?.toLocaleLowerCase() === baseName.toLocaleLowerCase())
      lastBaseIndex = index;
  }
  if (lastBaseIndex < 0) return null;

  const suffix = parts.slice(lastBaseIndex + 1);
  const canonical = `/${[...baseParts, ...suffix].join('/')}${
    pathname.endsWith('/') && suffix.length > 0 ? '/' : ''
  }`;
  return canonical === pathname ? null : canonical;
}

export function repairCurrentAppPath() {
  const canonical = canonicalAppPath(window.location.pathname);
  if (!canonical) return;
  window.history.replaceState(
    window.history.state,
    '',
    `${canonical}${window.location.search}${window.location.hash}`,
  );
}
