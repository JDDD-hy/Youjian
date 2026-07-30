import { ApiError } from './api';
import { getSupabaseClient } from './supabase';

const allowedClasses = new Set([
  'Error',
  'TypeError',
  'RangeError',
  'ReferenceError',
  'SyntaxError',
  'DOMException',
  'ApiError',
]);

export function safeRoute(pathname = window.location.pathname) {
  if (/\/(?:[^/]+\/)*invite\/[^/]+$/.test(pathname))
    return `${import.meta.env.BASE_URL}invite/:token`;
  return pathname.replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, ':id').slice(0, 200);
}

export function buildSafeErrorReport(error: unknown, source: string) {
  const name =
    error instanceof ApiError
      ? 'ApiError'
      : error instanceof Error && allowedClasses.has(error.name)
        ? error.name
        : 'Error';
  const code =
    error instanceof ApiError && /^[A-Z0-9_]{1,80}$/.test(error.code)
      ? error.code
      : 'UNEXPECTED_CLIENT_ERROR';
  return {
    errorCode: code,
    route: safeRoute(),
    metadata: {
      error_class: name,
      source: source.slice(0, 40),
      build: import.meta.env.MODE,
    },
  };
}

/** Best-effort diagnostic reporting. Never includes error messages or user content. */
export function reportSafeError(error: unknown, source: string) {
  const report = buildSafeErrorReport(error, source);
  console.error('[youjian]', {
    context: report.metadata.source,
    code: report.errorCode,
  });
  void Promise.resolve(
    getSupabaseClient().rpc('report_client_error', {
      p_error_code: report.errorCode,
      p_route: report.route,
      p_metadata: report.metadata,
    }),
  ).then(
    () => undefined,
    () => undefined,
  );
}
