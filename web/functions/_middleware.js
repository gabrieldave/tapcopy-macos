// Cloudflare Pages Functions middleware · tapcopy.iareal.net
// Geolocated language routing + mandatory Vary headers. Static assets bypass it.
import { resolveRedirect, VARY_VALUE } from './_lib/lang.js';

const ASSET = /\.[a-z0-9]{2,5}$/i; // /assets/site.css, /robots.txt, /TapCopy.dmg …

function withVary(response) {
  const res = new Response(response.body, response);
  res.headers.set('Vary', VARY_VALUE);
  return res;
}

export async function onRequest(context) {
  const { request, next } = context;
  const url = new URL(request.url);

  if (request.method !== 'GET' && request.method !== 'HEAD') return next();
  if (ASSET.test(url.pathname) || url.pathname.startsWith('/api/')) return next();

  const target = resolveRedirect({
    pathname: url.pathname,
    cookie: request.headers.get('Cookie'),
    country: request.headers.get('CF-IPCountry'),
    acceptLanguage: request.headers.get('Accept-Language'),
    userAgent: request.headers.get('User-Agent'),
  });

  if (target) {
    const location = new URL(target + url.search, url.origin);
    return new Response(null, {
      status: 302,
      headers: {
        Location: location.toString(),
        Vary: VARY_VALUE,
        'Cache-Control': 'private, no-store',
      },
    });
  }

  const response = await next();
  const contentType = response.headers.get('Content-Type') || '';
  return contentType.includes('text/html') ? withVary(response) : response;
}
