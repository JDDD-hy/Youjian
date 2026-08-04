import { lazy, type ComponentType } from 'react';

export function isChunkLoadError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return /Failed to fetch dynamically imported module|Importing a module script failed|Loading chunk \S+ failed/i.test(
    message,
  );
}

export function lazyRoute(
  routeName: string,
  loader: () => Promise<{ default: ComponentType }>,
) {
  return lazy(async () => {
    const reloadKey = `youjian:chunk-reload:${routeName}`;
    try {
      const loaded = await loader();
      sessionStorage.removeItem(reloadKey);
      return loaded;
    } catch (error) {
      if (isChunkLoadError(error) && !sessionStorage.getItem(reloadKey)) {
        sessionStorage.setItem(reloadKey, '1');
        window.location.reload();
        return new Promise<never>(() => undefined);
      }
      throw error;
    }
  });
}
