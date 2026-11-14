// TapCopy · WEB_FACTORY static builder (zero dependencies).
// node build.mjs  →  writes public/{index.html, es/index.html, privacy, terms, es/privacy, es/terms}
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const read = (p) => readFileSync(join(root, p), 'utf8');
const config = JSON.parse(read('site.config.json'));
const dict = { en: JSON.parse(read('src/i18n/en.json')), es: JSON.parse(read('src/i18n/es.json')) };
const tpl = { landing: read('src/templates/landing.html'), legal: read('src/templates/legal.html') };

// ---------- Guardrails: validated commercial data must never drift ----------
const money = (n) => Math.round(n * 100) / 100;
const p = Object.fromEntries(Object.entries(config.prices).map(([k, v]) => [k, Number(v)]));
const checks = [
  ['personal', p.personal === 7.99],
  ['pro', p.pro === 14.99],
  ['subscription3y', money(p.subscriptionYear * 3) === p.subscription3y],
  ['comboMin', money(12 + 4.99) === p.comboMin],
  ['comboMax', money(29 + 4.99) === p.comboMax],
  ['maxSavings', money(p.subscription3y - p.personal) === p.maxSavings],
  ['proSavings', money(p.subscription3y - p.pro) === p.proSavings],
  ['proPerMac', (p.pro / 3).toFixed(2) === config.prices.proPerMac],
];
for (const [name, ok] of checks) if (!ok) throw new Error(`Price guardrail failed: ${name}`);

// Both dictionaries must expose exactly the same keys.
const keys = (o, pre = '') => Object.entries(o).flatMap(([k, v]) =>
  v && typeof v === 'object' && !Array.isArray(v) ? keys(v, `${pre}${k}.`) : [`${pre}${k}`]);
const enKeys = new Set(keys(dict.en));
const esKeys = new Set(keys(dict.es));
const missing = [...enKeys].filter((k) => !esKeys.has(k)).concat([...esKeys].filter((k) => !enKeys.has(k)));
if (missing.length) throw new Error(`i18n key mismatch: ${missing.join(', ')}`);

// ---------- Helpers ----------
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const attrSafe = (s) => String(s).replace(/"/g, '&quot;');
const get = (obj, path) => path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
const LEGAL_PATHS = { privacy: { en: '/privacy', es: '/es/privacy' }, terms: { en: '/terms', es: '/es/terms' } };

function render(template, d, extra) {
  return template.replace(/\{\{(@?)([\w.]+)\}\}/g, (match, at, key) => {
    if (at) {
      if (!(key in extra)) throw new Error(`Missing build token @${key}`);
      return extra[key];
    }
    const v = get(d, key);
    if (v === undefined) throw new Error(`Missing i18n key ${key} (${d.lang})`);
    // Copy may carry inline <b>/<code>; attributes stay quote-safe.
    return attrSafe(v);
  });
}

function footer(d, otherPath) {
  const wa = `https://wa.me/${config.whatsapp}?text=${encodeURIComponent(d.whatsapp.message)}`;
  return `<footer class="footer">
  <div class="wrap footer__inner">
    <div class="footer__brand">
      <a class="brand" href="${d.home}" aria-label="TapCopy"><span class="brand__mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand__word">TapCopy</span></a>
      <p>${d.footer.product}</p>
    </div>
    <nav class="footer__links" aria-label="Legal">
      <a href="${d.base}/privacy">${d.footer.privacy}</a>
      <a href="${d.base}/terms">${d.footer.terms}</a>
      <a href="${otherPath}" data-set-lang="${d.otherLang}" hreflang="${d.otherLang}">${d.footer.langLabel}: ${d.otherLabel}</a>
    </nav>
    <p class="footer__legal">${d.footer.rights}<br>${d.footer.apple}</p>
  </div>
</footer>
<a class="wa" href="${wa}" target="_blank" rel="noopener" aria-label="${attrSafe(d.whatsapp.aria)}" data-cta="whatsapp">
  <svg viewBox="0 0 32 32" width="22" height="22" aria-hidden="true"><path fill="currentColor" d="M16 3a13 13 0 0 0-11.2 19.6L3 29l6.6-1.7A13 13 0 1 0 16 3Zm0 23.7c-2 0-4-.6-5.7-1.6l-.4-.2-3.9 1 1-3.8-.3-.4A10.7 10.7 0 1 1 16 26.7Zm5.9-8c-.3-.2-1.9-1-2.2-1-.3-.2-.5-.2-.7.1l-1 1.3c-.2.2-.4.2-.7 0a8.8 8.8 0 0 1-4.4-3.8c-.3-.6.3-.5 1-1.7.1-.2 0-.4 0-.6l-1-2.4c-.3-.6-.5-.5-.7-.5h-.6c-.2 0-.6 0-.9.4-.3.3-1.1 1.1-1.1 2.7s1.2 3.2 1.3 3.4c.2.2 2.3 3.5 5.6 5 2.1.8 2.9.9 4 .7.6-.1 1.9-.8 2.2-1.5.3-.8.3-1.4.2-1.5l-.6-.4Z"/></svg>
  <span class="wa__text"><b>${d.whatsapp.label}</b><small>${d.whatsapp.note}</small></span>
</a>`;
}

function i18nJson(d) {
  // Only the strings the client needs; "<" escaped so it can never close the script tag.
  return JSON.stringify({ lang: d.lang, hero: d.hero, pill: d.pill, tutorial: { soon: d.tutorial.soon } })
    .replace(/</g, '\\u003c');
}

function jsonld(d) {
  const offer = (name, price) => ({ '@type': 'Offer', name, price, priceCurrency: 'USD' });
  return JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'TapCopy',
    applicationCategory: 'UtilitiesApplication',
    operatingSystem: 'macOS 14 Sonoma or later',
    softwareVersion: config.version,
    inLanguage: d.htmlLang,
    description: d.meta.description,
    url: `${config.origin}${d.home}`,
    publisher: { '@type': 'Organization', name: 'BLACK EYE' },
    offers: [offer('Free trial (14 days)', '0'), offer('Personal', config.prices.personal), offer('Pro', config.prices.pro)],
  }).replace(/</g, '\\u003c');
}

function out(path, html) {
  const file = join(root, 'public', path === '/' ? 'index.html' : `${path.replace(/^\//, '')}/index.html`);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, html);
  return file.replace(root + '/', '');
}

const written = [];
for (const lang of ['en', 'es']) {
  const d = dict[lang];
  const other = dict[d.otherLang];
  const common = {
    origin: config.origin,
    version: config.version,
    fontsHref: esc(config.fontsHref),
    thisShort: lang.toUpperCase(),
    i18nJson: i18nJson(d),
  };

  written.push(out(d.home, render(tpl.landing, d, {
    ...common,
    canonical: `${config.origin}${d.home}`,
    otherHome: other.home,
    jsonld: jsonld(d),
    marquee: d.marquee.map((m) => `<span>${esc(m)}</span><i aria-hidden="true">◆</i>`).join(''),
    youtubeId: esc(config.youtubeId),
    trialEndpoint: config.trialEndpoint,
    downloadUrl: config.downloadUrl,
    checkoutPersonal: `${config.checkout.personal}?lang=${lang}`,
    checkoutPro: `${config.checkout.pro}?lang=${lang}`,
    footer: footer(d, other.home),
  })));

  for (const page of ['privacy', 'terms']) {
    const path = LEGAL_PATHS[page][lang];
    const otherPath = LEGAL_PATHS[page][d.otherLang];
    written.push(out(path, render(tpl.legal, d, {
      ...common,
      canonical: `${config.origin}${path}`,
      pathEn: LEGAL_PATHS[page].en,
      pathEs: LEGAL_PATHS[page].es,
      otherPath,
      legalTitle: esc(d.meta[`${page}Title`]),
      legalHeading: esc(d.legal[`${page}Heading`]),
      legalBody: d.legal[page].join('\n'),
      footer: footer(d, otherPath),
    })));
  }
}

// sitemap with hreflang pairs
const pairs = [['/', '/es/'], ['/privacy', '/es/privacy'], ['/terms', '/es/terms']];
const url = (loc, en, es) => `  <url><loc>${config.origin}${loc}</loc>
    <xhtml:link rel="alternate" hreflang="en" href="${config.origin}${en}"/>
    <xhtml:link rel="alternate" hreflang="es" href="${config.origin}${es}"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="${config.origin}${en}"/>
  </url>`;
writeFileSync(join(root, 'public/sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${pairs.flatMap(([en, es]) => [url(en, en, es), url(es, en, es)]).join('\n')}
</urlset>
`);
written.push('public/sitemap.xml');
console.log(`Built ${written.length} files:\n  ${written.join('\n  ')}`);
