// TapCopy · WEB_FACTORY · Language negotiation (pure, testable, no dependencies).
//
// Priority order (spec BLACK EYE):
//   1. Manual cookie `tapcopy-lang` (en | es, 1 year) set only by the on-page switcher.
//   2. CF-IPCountry in the Spanish-speaking list below.
//   3. Accept-Language fallback: first preferred language is `es*`.
//   4. Otherwise English (/), including the United States.
// SEO bots are NEVER redirected: they crawl both trees through hreflang.

export const COOKIE_NAME = 'tapcopy-lang';
export const COOKIE_MAX_AGE = 31536000; // 365 days

export const SPANISH_COUNTRIES = new Set([
  'MX', 'AR', 'BO', 'CL', 'CO', 'CR', 'CU', 'DO', 'EC', 'SV', 'GQ',
  'GT', 'HN', 'NI', 'PA', 'PY', 'PE', 'PR', 'ES', 'UY', 'VE',
]);

// Localised page pairs. Anything not listed here is never redirected.
export const ROUTES = {
  '/': '/es/',
  '/privacy': '/es/privacy',
  '/terms': '/es/terms',
};

const BOT_PATTERN = new RegExp(
  [
    'googlebot', 'google-inspectiontool', 'adsbot-google', 'mediapartners-google',
    'bingbot', 'msnbot', 'duckduckbot', 'yandex', 'baiduspider', 'slurp',
    'applebot', 'petalbot', 'seznambot', 'sogou', 'exabot',
    'facebookexternalhit', 'facebot', 'twitterbot', 'linkedinbot', 'slackbot',
    'discordbot', 'telegrambot', 'whatsapp', 'pinterest', 'embedly',
    'ahrefsbot', 'semrushbot', 'mj12bot', 'dotbot', 'rogerbot', 'screaming frog',
    'lighthouse', 'chrome-lighthouse', 'gptbot', 'oai-searchbot', 'claudebot',
    'perplexitybot', 'ccbot', 'bytespider', '\\bbot\\b', 'crawler', 'spider',
  ].join('|'),
  'i',
);

export function isBot(userAgent) {
  if (!userAgent) return true; // no UA → treat as non-human, never redirect
  return BOT_PATTERN.test(userAgent);
}

export function readLangCookie(cookieHeader) {
  if (!cookieHeader) return null;
  for (const part of cookieHeader.split(';')) {
    const [rawKey, ...rest] = part.trim().split('=');
    if (rawKey === COOKIE_NAME) {
      const value = rest.join('=').trim().toLowerCase();
      return value === 'en' || value === 'es' ? value : null;
    }
  }
  return null;
}

export function primaryAcceptLanguage(header) {
  if (!header) return null;
  const ranked = header
    .split(',')
    .map((entry, index) => {
      const [tag, ...params] = entry.trim().split(';');
      const q = params.find((p) => p.trim().startsWith('q='));
      const weight = q ? Number.parseFloat(q.trim().slice(2)) : 1;
      return { tag: tag.trim().toLowerCase(), weight: Number.isFinite(weight) ? weight : 0, index };
    })
    .filter((e) => e.tag && e.tag !== '*' && e.weight > 0)
    .sort((a, b) => b.weight - a.weight || a.index - b.index);
  return ranked.length ? ranked[0].tag : null;
}

/** Returns { lang, source } for a human visitor. */
export function preferredLang({ cookie, country, acceptLanguage }) {
  const manual = readLangCookie(cookie);
  if (manual) return { lang: manual, source: 'cookie' };
  const cc = (country || '').toUpperCase();
  if (SPANISH_COUNTRIES.has(cc)) return { lang: 'es', source: 'country' };
  const al = primaryAcceptLanguage(acceptLanguage);
  if (al && al.startsWith('es')) return { lang: 'es', source: 'accept-language' };
  return { lang: 'en', source: 'default' };
}

function normalizePath(pathname) {
  if (pathname === '/es') return '/es/';
  if (pathname.length > 1 && pathname.endsWith('/') && pathname !== '/es/') {
    return pathname.slice(0, -1);
  }
  return pathname;
}

/**
 * Decides whether a request must be redirected to the other language tree.
 * Returns the target path or null.
 */
export function resolveRedirect({ pathname, cookie, country, acceptLanguage, userAgent }) {
  if (isBot(userAgent)) return null;
  const path = normalizePath(pathname);
  const enToEs = ROUTES;
  const esToEn = Object.fromEntries(Object.entries(ROUTES).map(([en, es]) => [es, en]));
  const isEnPage = Object.prototype.hasOwnProperty.call(enToEs, path);
  const isEsPage = Object.prototype.hasOwnProperty.call(esToEn, path);
  if (!isEnPage && !isEsPage) return null;

  const { lang, source } = preferredLang({ cookie, country, acceptLanguage });

  // Spanish visitor landing on an English page → /es/…
  if (isEnPage && lang === 'es') return enToEs[path];
  // Only an explicit manual choice moves someone OUT of /es/ (deep links stay put).
  if (isEsPage && lang === 'en' && source === 'cookie') return esToEn[path];
  return null;
}

export const VARY_VALUE = 'CF-IPCountry, Cookie, Accept-Language';
