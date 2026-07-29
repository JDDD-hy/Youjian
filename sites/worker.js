const securityHeaders = {
  'Content-Security-Policy':
    "default-src 'self'; script-src 'self' https://challenges.cloudflare.com; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://*.supabase.co wss://*.supabase.co https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; manifest-src 'self'; worker-src 'self' blob:; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'",
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-Content-Type-Options': 'nosniff',
};

function withSecurityHeaders(response, pathname) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(securityHeaders))
    headers.set(name, value);
  if (pathname === '/sw.js') headers.set('Cache-Control', 'no-cache');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    let response = await env.ASSETS.fetch(request);
    if (
      response.status === 404 &&
      request.method === 'GET' &&
      request.headers.get('Accept')?.includes('text/html')
    ) {
      const fallback = new URL('/index.html', url);
      response = await env.ASSETS.fetch(new Request(fallback, request));
    }
    return withSecurityHeaders(response, url.pathname);
  },
};
