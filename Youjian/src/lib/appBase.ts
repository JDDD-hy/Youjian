export const appBasePath = import.meta.env.BASE_URL;

export function appPath(path = '') {
  const suffix = path.replace(/^\/+/, '');
  return `${appBasePath}${suffix}`;
}
