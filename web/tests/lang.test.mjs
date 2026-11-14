// node --test web/tests/lang.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveRedirect, preferredLang, primaryAcceptLanguage, isBot } from '../functions/_lib/lang.js';

const CHROME = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const r = (o) => resolveRedirect({ userAgent: CHROME, ...o });

test('Mexico first visit → /es/', () => assert.equal(r({ pathname: '/', country: 'MX' }), '/es/'));
test('every listed country → es', () => {
  for (const cc of 'MX AR BO CL CO CR CU DO EC SV GQ GT HN NI PA PY PE PR ES UY VE'.split(' ')) {
    assert.equal(r({ pathname: '/', country: cc }), '/es/', cc);
  }
});
test('United States default → stays on /', () => assert.equal(r({ pathname: '/', country: 'US', acceptLanguage: 'en-US,en;q=0.9' }), null));
test('Brazil default → English', () => assert.equal(r({ pathname: '/', country: 'BR', acceptLanguage: 'pt-BR' }), null));
test('US visitor with Spanish browser → es (Accept-Language fallback)', () =>
  assert.equal(r({ pathname: '/', country: 'US', acceptLanguage: 'es-US,es;q=0.9,en;q=0.8' }), '/es/'));
test('Accept-Language es only as secondary → English', () =>
  assert.equal(r({ pathname: '/', country: 'US', acceptLanguage: 'en-US,es;q=0.5' }), null));
test('cookie en beats Mexico IP', () => assert.equal(r({ pathname: '/', country: 'MX', cookie: 'tapcopy-lang=en' }), null));
test('cookie en on /es/ → back to /', () => assert.equal(r({ pathname: '/es/', country: 'MX', cookie: 'a=1; tapcopy-lang=en' }), '/'));
test('cookie es on / from US → /es/', () => assert.equal(r({ pathname: '/', country: 'US', cookie: 'tapcopy-lang=es' }), '/es/'));
test('US visitor deep-linked to /es/ without cookie → stays', () => assert.equal(r({ pathname: '/es/', country: 'US' }), null));
test('legal pages map', () => {
  assert.equal(r({ pathname: '/privacy', country: 'AR' }), '/es/privacy');
  assert.equal(r({ pathname: '/terms/', country: 'CL' }), '/es/terms');
  assert.equal(r({ pathname: '/es/terms', cookie: 'tapcopy-lang=en' }), '/terms');
});
test('/es without slash normalises', () => assert.equal(r({ pathname: '/es', cookie: 'tapcopy-lang=en' }), '/'));
test('unknown paths never redirect', () => assert.equal(r({ pathname: '/checkout/pro', country: 'MX' }), null));
test('bots never redirected', () => {
  for (const ua of ['Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
    'Mozilla/5.0 (compatible; bingbot/2.0)', 'facebookexternalhit/1.1', 'Mozilla/5.0 AppleWebKit (KHTML) Applebot/0.1', '']) {
    assert.equal(resolveRedirect({ pathname: '/', country: 'MX', userAgent: ua }), null, ua);
  }
  assert.equal(isBot(CHROME), false);
});
test('invalid cookie value ignored', () => assert.deepEqual(preferredLang({ cookie: 'tapcopy-lang=fr', country: 'MX' }), { lang: 'es', source: 'country' }));
test('q-weights respected', () => assert.equal(primaryAcceptLanguage('en;q=0.4, es-MX;q=0.9'), 'es-mx'));
