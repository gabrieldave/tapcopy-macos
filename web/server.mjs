import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

import { db, migrate, dbHealthy } from './lib/db.mjs';
import { licenseToken, updateManifestSignature, sign } from './lib/crypto.mjs';
import { sendMail, welcomeMail, receiptMail } from './lib/mail.mjs';
import { PLANS, createCheckout, verifyWebhook, notifyN8n } from './lib/stripe.mjs';
import {
  ADMIN_EMAIL, authUrl, exchangeCode, readSession, sessionCookie, clearCookie, stateCookie,
  readOAuthState, clearStateCookie,
} from './lib/auth.mjs';
import { clientIp, rateLimiter, hashLicenseKey, maskKey } from './lib/security.mjs';
import { resolveRedirect, VARY_VALUE } from './functions/_lib/lang.js';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(ROOT, 'public');
const STORAGE_DIR = process.env.STORAGE_DIR || '/app/storage';
const ORIGIN = process.env.PUBLIC_URL || 'https://tapcopy.iareal.net';
const PORT = Number(process.env.PORT || 3000);
const VERSION = process.env.APP_VERSION || '1.1.1';
const BUILD = Number(process.env.APP_BUILD || 6);
const DMG_NAME = `TapCopy-${VERSION}.dmg`;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.woff2': 'font/woff2',
  '.dmg': 'application/x-apple-diskimage',
};

// ---------------------------------------------------------------- headers ---
function parseHeadersFile() {
  const out = {};
  try {
    const raw = fs.readFileSync(path.join(PUBLIC_DIR, '_headers'), 'utf8');
    let current = null;
    for (const line of raw.split('\n')) {
      if (!line.trim() || line.trim().startsWith('#')) continue;
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        current = line.trim();
        out[current] = out[current] || [];
      } else if (current) {
        const idx = line.indexOf(':');
        if (idx > 0) out[current].push([line.slice(0, idx).trim(), line.slice(idx + 1).trim()]);
      }
    }
  } catch {
    /* no _headers file */
  }
  return out;
}

const HEADER_RULES = parseHeadersFile();

function securityHeaders(filePath) {
  const headers = {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'SAMEORIGIN',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'clipboard-write=(self), geolocation=(), microphone=(), camera=()',
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  };
  for (const [pattern, list] of Object.entries(HEADER_RULES)) {
    if (pattern === '/*' || (pattern.endsWith('*') && filePath.startsWith(pattern.slice(0, -1))) || pattern === filePath) {
      for (const [k, v] of list) headers[k] = v;
    }
  }
  return headers;
}

function send(res, status, body, headers = {}) {
  const payload = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'SAMEORIGIN',
    ...headers,
  });
  res.end(payload);
}

/// Fixed-window IP limiter (10 attempts / 15 min per bucket).
function enforceRateLimit(req, res, bucket) {
  const verdict = rateLimiter.check(`${clientIp(req)}:${bucket}`);
  if (verdict.allowed) return true;
  send(res, 429, { error: 'rate_limited' }, { 'Retry-After': String(verdict.retryAfter) });
  return false;
}

async function readBody(req, limit = 1_000_000) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new Error('payload_too_large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

// ------------------------------------------------------------------ keys ---
const KEY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateKey() {
  const group = () => {
    let out = '';
    const bytes = crypto.randomBytes(4);
    for (let i = 0; i < 4; i += 1) out += KEY_ALPHABET[bytes[i] % KEY_ALPHABET.length];
    return out;
  };
  return `TCOPY-${group()}-${group()}-${group()}`;
}

// ------------------------------------------------------- key at rest (AES) ---
// Licenses are still looked up by their literal TCOPY-… value (the app posts it
// verbatim), but the admin panel must be able to show/mail the full key on
// demand, so we keep a recoverable AES-256-GCM copy derived from the server
// secret. The key material never leaves the container.
const ENC_SECRET = process.env.TAPCOPY_LICENSE_ENC_KEY || process.env.SESSION_SECRET || '';
const ENC_KEY = ENC_SECRET
  ? Buffer.from(
      crypto.hkdfSync('sha256', Buffer.from(ENC_SECRET), Buffer.from('tapcopy-license-v1'), Buffer.from('aes-256-gcm-license-key'), 32),
    )
  : null;

function encryptLicenseKey(plain) {
  if (!ENC_KEY || !plain) return null;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', ENC_KEY, iv);
  const ciphertext = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.');
}

function decryptLicenseKey(blob) {
  if (!ENC_KEY || !blob) return null;
  try {
    const [version, ivB64, tagB64, dataB64] = String(blob).split('.');
    if (version !== 'v1' || !ivB64 || !tagB64 || !dataB64) return null;
    const decipher = crypto.createDecipheriv('aes-256-gcm', ENC_KEY, Buffer.from(ivB64, 'base64url'));
    decipher.setAuthTag(Buffer.from(tagB64, 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(dataB64, 'base64url')), decipher.final()]).toString('utf8');
  } catch {
    return null;
  }
}

/// Backfills `key_hash` (SHA-256) and `key_encrypted` (AES-256-GCM) on existing
/// databases. Only after both are confirmed does it replace `licenses.key` with
/// the masked value, so a SQL dump can never expose a usable key.
async function ensureKeyEncryption() {
  try {
    await db.query('ALTER TABLE licenses ADD COLUMN IF NOT EXISTS key_encrypted TEXT');
    await db.query('ALTER TABLE licenses ADD COLUMN IF NOT EXISTS key_hash TEXT');
    const pending = await db.query('SELECT id, key, key_hash, key_encrypted FROM licenses');
    let hashed = 0;
    let masked = 0;
    for (const row of pending.rows) {
      const raw = String(row.key || '');
      const alreadyMasked = raw.includes('••••');
      let hash = row.key_hash || null;
      let cipher = row.key_encrypted || null;
      if (!hash && !alreadyMasked && KEY_RE.test(raw)) hash = hashLicenseKey(raw);
      if (!cipher && !alreadyMasked && KEY_RE.test(raw) && ENC_KEY) cipher = encryptLicenseKey(raw);
      if (!hash) continue; // unrecoverable legacy row: leave it untouched
      if (!row.key_hash) {
        await db.query('UPDATE licenses SET key_hash = $1 WHERE id = $2', [hash, row.id]);
        hashed += 1;
      }
      if (!row.key_encrypted && cipher) {
        await db.query('UPDATE licenses SET key_encrypted = $1 WHERE id = $2', [cipher, row.id]);
      }
      if (!alreadyMasked && cipher) {
        await db.query('UPDATE licenses SET key = $1 WHERE id = $2', [maskKey(raw), row.id]);
        masked += 1;
      }
    }
    if (hashed || masked) console.log(`license keys hashed: ${hashed}, masked: ${masked}`);
    if (!ENC_KEY) console.warn('license encryption disabled: missing SESSION_SECRET (keys stay unmasked)');
  } catch (err) {
    console.error('key encryption init failed', err.message);
  }
}

/// Full key for an admin action: prefer the encrypted copy, fall back to the
/// legacy plaintext column for rows that predate the backfill. Masked values
/// are never returned as a "full" key.
function fullLicenseKey(row) {
  const plain = decryptLicenseKey(row.key_encrypted);
  if (plain) return plain;
  const legacy = String(row.key || '');
  return legacy && !legacy.includes('••••') ? legacy : null;
}

// ------------------------------------------------------------------ trial ---
async function handleTrial(req, res) {
  if (!enforceRateLimit(req, res, 'trial')) return;
  const raw = await readBody(req);
  const type = req.headers['content-type'] || '';
  let email = null;
  let lang = 'en';
  let wantsForm = false;

  if (type.includes('application/json')) {
    const body = JSON.parse(raw || '{}');
    email = typeof body.email === 'string' && body.email.includes('@') ? body.email.trim().toLowerCase() : null;
    lang = body.lang === 'es' ? 'es' : 'en';
  } else {
    const params = new URLSearchParams(raw);
    const candidate = params.get('email');
    email = candidate && candidate.includes('@') ? candidate.trim().toLowerCase() : null;
    lang = params.get('lang') === 'es' ? 'es' : 'en';
    wantsForm = true;
  }

  const country = (req.headers['cf-ipcountry'] || '').toString().slice(0, 2).toUpperCase() || null;
  try {
    await db.query(
      'INSERT INTO trial_leads (email, lang, ip_country, source) VALUES ($1,$2,$3,$4)',
      [email, lang, country, wantsForm ? 'form' : 'landing'],
    );
  } catch (err) {
    console.error('trial lead insert failed', err.message);
  }

  if (email) {
    const mail = welcomeMail(lang, `${ORIGIN}/download/TapCopy.dmg`);
    sendMail({ to: email, ...mail }).catch(() => {});
  }

  if (wantsForm) {
    res.writeHead(303, { Location: '/download/TapCopy.dmg', 'Cache-Control': 'no-store' });
    return res.end();
  }
  send(res, 200, { downloadUrl: '/download/TapCopy.dmg' });
}

// ----------------------------------------------------------- trial sync ---
async function handleTrialSync(req, res) {
  if (!enforceRateLimit(req, res, 'trial')) return;

  let body;
  try {
    body = JSON.parse((await readBody(req, 8 * 1024)) || '{}');
  } catch {
    return send(res, 413, { error: 'payload_too_large' });
  }

  const deviceId = String(body.deviceId || '');
  const appVersion = typeof body.appVersion === 'string' ? body.appVersion.slice(0, 32) : null;
  if (!/^[a-f0-9]{64}$/.test(deviceId)) return send(res, 400, { error: 'invalid_device' });

  const result = await db.query(
    `INSERT INTO hardware_trials (device_id, app_version)
     VALUES ($1, $2)
     ON CONFLICT (device_id) DO UPDATE SET
       last_seen = now(),
       app_version = COALESCE(EXCLUDED.app_version, hardware_trials.app_version),
       sync_count = hardware_trials.sync_count + 1
     RETURNING EXTRACT(EPOCH FROM first_seen)::double precision AS first_seen,
               EXTRACT(EPOCH FROM now())::double precision AS server_now`,
    [deviceId, appVersion],
  );

  send(res, 200, {
    firstSeen: result.rows[0].first_seen,
    serverNow: result.rows[0].server_now,
  }, { 'Cache-Control': 'no-store' });
}

// -------------------------------------------------------------- download ---
function dmgPath() {
  const candidates = [path.join(STORAGE_DIR, DMG_NAME), path.join(STORAGE_DIR, 'TapCopy.dmg')];
  for (const candidate of candidates) {
    try {
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch {
      /* keep looking */
    }
  }
  return null;
}

async function handleDownload(req, res) {
  const file = dmgPath();
  if (!file) return send(res, 503, { error: 'release_unavailable' });
  const stat = await fsp.stat(file);
  let sha = '';
  try {
    const manifest = JSON.parse(await fsp.readFile(path.join(STORAGE_DIR, 'latest.json'), 'utf8'));
    sha = manifest.sha256 || '';
  } catch {
    /* header is optional but expected in production */
  }
  res.writeHead(200, {
    'Content-Type': 'application/x-apple-diskimage',
    'Content-Length': stat.size,
    'Content-Disposition': `attachment; filename="${DMG_NAME}"`,
    'Cache-Control': 'no-store',
    ...(sha ? { 'X-SHA256': sha } : {}),
    ...securityHeaders('/download/TapCopy.dmg'),
  });
  fs.createReadStream(file).pipe(res);
}

// ----------------------------------------------------------------- update ---
async function handleManifest(req, res) {
  try {
    const raw = await fsp.readFile(path.join(STORAGE_DIR, 'latest.json'), 'utf8');
    const manifest = JSON.parse(raw);
    send(res, 200, manifest, {
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      Pragma: 'no-cache',
      Expires: '0',
    });
  } catch {
    send(res, 503, { error: 'manifest_unavailable' });
  }
}

// --------------------------------------------------------------- checkout ---
async function handleCheckout(req, res, plan, url) {
  const lang = url.searchParams.get('lang') === 'es' ? 'es' : 'en';
  try {
    const session = await createCheckout({ plan, lang, origin: ORIGIN });
    notifyN8n({
      app: 'tapcopy',
      event: 'checkout_created',
      plan,
      seats: PLANS[plan]?.seats,
      lang,
      sessionId: session.id,
    });
    res.writeHead(303, { Location: session.url, 'Cache-Control': 'no-store' });
    res.end();
  } catch (err) {
    console.error('checkout failed', err.message);
    send(res, 503, { error: 'checkout_unavailable', detail: err.message });
  }
}

// ---------------------------------------------------------------- webhook ---
async function handleStripeWebhook(req, res) {
  const raw = await readBody(req);
  const check = verifyWebhook(raw, req.headers['stripe-signature']);
  if (!check.ok) return send(res, 400, { error: check.reason });
  const event = check.event;
  if (!event.id) return send(res, 400, { error: 'invalid_event' });

  const claimed = await db.query(
    `INSERT INTO stripe_events (event_id, event_type) VALUES ($1, $2)
     ON CONFLICT (event_id) DO NOTHING RETURNING event_id`,
    [event.id, event.type],
  );
  if (claimed.rowCount === 0) return send(res, 200, { received: true, duplicate: true });

  try {
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const plan = session.metadata?.plan === 'pro' ? 'pro' : 'personal';
      const seats = Number(session.metadata?.seats || PLANS[plan].seats);
      const lang = session.metadata?.lang === 'es' ? 'es' : 'en';
      const email = session.customer_details?.email || session.customer_email || null;
      const amount = Number(session.amount_total || PLANS[plan].amountCents);

      const existing = await db.query('SELECT id FROM orders WHERE stripe_session_id = $1', [session.id]);
      if (existing.rowCount === 0) {
        const order = await db.query(
          `INSERT INTO orders (stripe_session_id, stripe_payment_intent, email, plan, seats, amount_cents, lang, status)
           VALUES ($1,$2,$3,$4,$5,$6,$7,'paid') RETURNING id`,
          [session.id, session.payment_intent || null, email, plan, seats, amount, lang],
        );
        const key = generateKey();
        await db.query(
          `INSERT INTO licenses (key, key_hash, key_encrypted, plan, seats, email, order_id, issued_by)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
          [maskKey(key), hashLicenseKey(key), encryptLicenseKey(key), plan, seats, email, order.rows[0].id, 'stripe'],
        );
        if (email) {
          const mail = receiptMail(lang, { key, plan, seats, amount: (amount / 100).toFixed(2) });
          await sendMail({ to: email, ...mail }).catch(() => {});
        }
        notifyN8n({
          app: 'tapcopy',
          event: 'license_issued',
          plan,
          seats,
          key: maskKey(key),
          amount: (amount / 100).toFixed(2),
          currency: 'usd',
          sessionId: session.id,
        });
      }
    } else if (event.type === 'charge.refunded' || event.type === 'charge.dispute.created') {
      const charge = event.data.object;
      const intent = charge.payment_intent || charge.id;
      const order = await db.query('SELECT id FROM orders WHERE stripe_payment_intent = $1', [intent]);
      if (order.rowCount) {
        await db.query(
          "UPDATE licenses SET status = 'refunded', refunded_at = now() WHERE order_id = $1",
          [order.rows[0].id],
        );
        await db.query("UPDATE orders SET status = 'refunded' WHERE id = $1", [order.rows[0].id]);
      }
    }
  } catch (err) {
    await db.query('DELETE FROM stripe_events WHERE event_id = $1', [event.id]).catch(() => {});
    console.error('webhook processing error', err.message);
    return send(res, 500, { error: 'webhook_failed' });
  }
  send(res, 200, { received: true });
}

// --------------------------------------------------------------- licenses ---
const KEY_RE = /^TCOPY-[A-Z0-9]{4}(-[A-Z0-9]{4}){2}$/;

async function handleActivate(req, res) {
  if (!enforceRateLimit(req, res, 'license')) return;
  const body = JSON.parse((await readBody(req)) || '{}');
  const key = String(body.key || '').trim().toUpperCase();
  const deviceId = String(body.deviceId || '').trim();
  const macName = String(body.macName || '').slice(0, 80);

  if (!KEY_RE.test(key) || !deviceId) return send(res, 400, { error: 'invalid_key' });

  const found = await db.query('SELECT * FROM licenses WHERE key_hash = $1 OR key = $2', [hashLicenseKey(key), key]);
  if (found.rowCount === 0) return send(res, 404, { error: 'invalid_key' });
  const license = found.rows[0];
  if (license.status === 'refunded') return send(res, 409, { error: 'refunded' });
  if (license.status !== 'active') return send(res, 409, { error: 'invalid_key' });

  const seats = await db.query('SELECT device_id FROM license_activations WHERE license_id = $1', [license.id]);
  const current = seats.rows.map((r) => r.device_id);
  if (!current.includes(deviceId) && current.length >= license.seats) {
    return send(res, 409, { error: 'seat_limit', seats: license.seats });
  }

  await db.query(
    `INSERT INTO license_activations (license_id, device_id, mac_name)
     VALUES ($1,$2,$3)
     ON CONFLICT (license_id, device_id) DO UPDATE SET last_seen = now(), mac_name = EXCLUDED.mac_name`,
    [license.id, deviceId, macName || null],
  );

  send(res, 200, {
    token: licenseToken({ key, plan: license.plan, seats: license.seats, deviceId }),
    plan: license.plan,
    seats: license.seats,
    maskedKey: maskKey(key),
  });
}

async function handleDeactivate(req, res) {
  if (!enforceRateLimit(req, res, 'license')) return;
  const body = JSON.parse((await readBody(req)) || '{}');
  const key = String(body.key || '').trim().toUpperCase();
  const deviceId = String(body.deviceId || '').trim();
  if (!KEY_RE.test(key) || !deviceId) return send(res, 400, { error: 'invalid_key' });
  const found = await db.query('SELECT id FROM licenses WHERE key_hash = $1 OR key = $2', [hashLicenseKey(key), key]);
  if (found.rowCount === 0) return send(res, 404, { error: 'invalid_key' });
  await db.query('DELETE FROM license_activations WHERE license_id = $1 AND device_id = $2', [
    found.rows[0].id,
    deviceId,
  ]);
  send(res, 200, { ok: true });
}

// ------------------------------------------------------------------ admin ---
function adminGate(req, res) {
  const session = readSession(req.headers.cookie);
  if (!session) {
    send(res, req.url.startsWith('/api/') ? 401 : 403, { error: 'unauthorized' });
    return null;
  }
  return session;
}

async function adminStats() {
  const [revenue, orders, licenses, activations, leads, recent] = await Promise.all([
    db.query("SELECT COALESCE(SUM(amount_cents),0)::int AS cents, COUNT(*)::int AS count FROM orders WHERE status = 'paid'"),
    db.query('SELECT COUNT(*)::int AS count FROM orders'),
    db.query("SELECT COUNT(*)::int AS total, COUNT(*) FILTER (WHERE status = 'active')::int AS active FROM licenses"),
    db.query('SELECT COUNT(*)::int AS used FROM license_activations'),
    db.query("SELECT COUNT(*)::int AS total, COUNT(*) FILTER (WHERE created_at > now() - interval '7 days')::int AS week FROM trial_leads"),
    db.query(
      `SELECT l.id, l.key, l.plan, l.seats, l.status, l.email, l.created_at,
              (l.key_encrypted IS NOT NULL) AS has_cipher,
              COUNT(a.id)::int AS used
       FROM licenses l LEFT JOIN license_activations a ON a.license_id = l.id
       GROUP BY l.id ORDER BY l.created_at DESC LIMIT 100`,
    ),
  ]);

  let manifest = null;
  try {
    manifest = JSON.parse(await fsp.readFile(path.join(STORAGE_DIR, 'latest.json'), 'utf8'));
  } catch {
    manifest = null;
  }

  const leadsList = await db.query(
    'SELECT email, lang, ip_country, source, created_at FROM trial_leads ORDER BY created_at DESC LIMIT 50',
  );

  return {
    revenueCents: revenue.rows[0].cents,
    paidOrders: revenue.rows[0].count,
    totalOrders: orders.rows[0].count,
    licenses: licenses.rows[0],
    seatsUsed: activations.rows[0].used,
    leads: leads.rows[0],
    leadsList: leadsList.rows,
    recent: recent.rows.map((r) => ({
      id: r.id,
      maskedKey: maskKey(r.key),
      plan: r.plan,
      seats: r.seats,
      used: r.used,
      status: r.status,
      email: r.email,
      created_at: r.created_at,
      hasCipher: !!r.has_cipher,
    })),
    manifest,
    version: VERSION,
    build: BUILD,
  };
}

async function handleAdminApi(req, res, url, session) {
  const action = url.pathname.replace('/api/admin/', '');

  if (action === 'me') return send(res, 200, { email: session.email });
  if (action === 'stats') return send(res, 200, await adminStats());

  if (action === 'licenses' && req.method === 'POST') {
    const body = JSON.parse((await readBody(req)) || '{}');
    const plan = body.plan === 'pro' ? 'pro' : 'personal';
    const seats = plan === 'pro' ? 3 : 1;
    const email = typeof body.email === 'string' && body.email.includes('@') ? body.email.toLowerCase() : null;
    const key = generateKey();
    await db.query(
      `INSERT INTO licenses (key, key_hash, key_encrypted, plan, seats, email, issued_by)
       VALUES ($1,$2,$3,$4,$5,$6,'admin')`,
      [maskKey(key), hashLicenseKey(key), encryptLicenseKey(key), plan, seats, email],
    );
    await db.query('INSERT INTO admin_audit (email, action, detail) VALUES ($1,$2,$3)', [
      session.email,
      'issue',
      maskKey(key),
    ]);
    if (email) {
      const mail = receiptMail('en', { key, plan, seats, amount: (PLANS[plan].amountCents / 100).toFixed(2) });
      await sendMail({ to: email, ...mail }).catch(() => {});
    }
    return send(res, 200, { key });
  }

  // Everything below is addressed by the numeric row id — the admin never has
  // to know or type a TCOPY-… key.
  const match = action.match(/^licenses\/(\d+)(?:\/(key|resend|revoke|reactivate))?$/);
  if (!match) return send(res, 404, { error: 'not_found' });

  const id = Number(match[1]);
  const sub = match[2] || '';
  const found = await db.query('SELECT * FROM licenses WHERE id = $1', [id]);
  if (found.rowCount === 0) return send(res, 404, { error: 'not_found' });
  const license = found.rows[0];

  if (!sub) {
    if (req.method === 'DELETE') {
      await db.query('DELETE FROM license_activations WHERE license_id = $1', [id]);
      await db.query('DELETE FROM licenses WHERE id = $1', [id]);
      await db.query('INSERT INTO admin_audit (email, action, detail) VALUES ($1,$2,$3)', [
        session.email,
        'delete',
        `${maskKey(license.key)} (#${id})`,
      ]);
      return send(res, 200, { ok: true, deleted: id });
    }
    if (req.method === 'GET') {
      return send(res, 200, {
        id: license.id,
        maskedKey: maskKey(license.key),
        plan: license.plan,
        seats: license.seats,
        status: license.status,
        email: license.email,
        hasCipher: Boolean(license.key_encrypted),
      });
    }
    return send(res, 405, { error: 'method_not_allowed' });
  }

  if (sub === 'key') {
    const full = fullLicenseKey(license);
    if (!full) return send(res, 409, { error: 'no_key_stored', id });
    return send(res, 200, { id, key: full, maskedKey: maskKey(license.key) });
  }

  if (sub === 'resend') {
    if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
    const body = JSON.parse((await readBody(req)) || '{}');
    let target = license.email ? String(license.email).trim().toLowerCase() : '';
    if (!target) {
      const candidate = String(body.email || '').trim().toLowerCase();
      if (!candidate.includes('@')) return send(res, 400, { error: 'email_required', id });
      target = candidate;
      await db.query('UPDATE licenses SET email = $1 WHERE id = $2', [target, id]);
    }
    const full = fullLicenseKey(license);
    if (!full) return send(res, 409, { error: 'no_key_stored', id });

    let lang = 'en';
    if (license.order_id) {
      const order = await db.query('SELECT lang FROM orders WHERE id = $1', [license.order_id]);
      if (order.rowCount && order.rows[0].lang === 'es') lang = 'es';
    }
    const mail = receiptMail(lang, {
      key: full,
      plan: license.plan,
      seats: license.seats,
      amount: (PLANS[license.plan].amountCents / 100).toFixed(2),
    });
    const result = await sendMail({ to: target, ...mail });
    await db.query('INSERT INTO admin_audit (email, action, detail) VALUES ($1,$2,$3)', [
      session.email,
      'resend',
      `${maskKey(license.key)} → ${target}`,
    ]);
    if (!result.ok) return send(res, 502, { error: 'mail_failed', id, to: target });
    return send(res, 200, { sent: true, to: target, id });
  }

  if (sub === 'revoke' || sub === 'reactivate') {
    if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
    if (sub === 'revoke') {
      await db.query("UPDATE licenses SET status = 'revoked', revoked_at = now() WHERE id = $1", [id]);
      await db.query('INSERT INTO admin_audit (email, action, detail) VALUES ($1,$2,$3)', [
        session.email,
        'revoke',
        `${maskKey(license.key)} (#${id})`,
      ]);
      return send(res, 200, { ok: true, id, status: 'revoked' });
    }
    await db.query("UPDATE licenses SET status = 'active', revoked_at = NULL WHERE id = $1", [id]);
    await db.query('INSERT INTO admin_audit (email, action, detail) VALUES ($1,$2,$3)', [
      session.email,
      'reactivate',
      `${maskKey(license.key)} (#${id})`,
    ]);
    return send(res, 200, { ok: true, id, status: 'active' });
  }

  return send(res, 404, { error: 'not_found' });
}

// ----------------------------------------------------------------- static ---
async function serveStatic(req, res, url) {
  let pathname = decodeURIComponent(url.pathname);
  if (pathname === '/') pathname = '/index.html';
  if (pathname.endsWith('/')) pathname += 'index.html';

  const targetPath = path.join(PUBLIC_DIR, path.normalize(pathname));
  if (!targetPath.startsWith(PUBLIC_DIR)) return send(res, 403, { error: 'forbidden' });

  let filePath = targetPath;
  try {
    const stat = await fsp.stat(filePath);
    if (stat.isDirectory()) filePath = path.join(filePath, 'index.html');
  } catch {
    // Clean URLs: /privacy → /privacy/index.html
    try {
      const alt = path.join(PUBLIC_DIR, path.normalize(`${pathname}/index.html`));
      await fsp.access(alt);
      filePath = alt;
    } catch {
      return send(res, 404, { error: 'not_found' }, securityHeaders(pathname));
    }
  }

  const ext = path.extname(filePath).toLowerCase();
  const headers = {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Cache-Control': ext === '.html' ? 'public, max-age=0, must-revalidate' : 'public, max-age=3600',
    ...securityHeaders(pathname),
  };
  if (url.pathname.startsWith('/assets/')) {
    headers['Cache-Control'] = 'public, max-age=31536000, immutable';
  }
  res.writeHead(200, headers);
  fs.createReadStream(filePath).pipe(res);
}

// ----------------------------------------------------------------- router ---
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, ORIGIN);
  const pathname = url.pathname;

  try {
    if (req.method === 'GET' && pathname === '/api/health') {
      const healthy = await dbHealthy();
      return send(res, healthy ? 200 : 503, {
        ok: healthy,
        app: 'TapCopy',
        version: VERSION,
        build: BUILD,
        db: healthy,
      });
    }

    if (req.method === 'POST' && pathname === '/api/trial') return await handleTrial(req, res);
    if (req.method === 'POST' && pathname === '/api/trial/sync') return await handleTrialSync(req, res);
    if (req.method === 'GET' && pathname === '/download/TapCopy.dmg') return await handleDownload(req, res);
    if (req.method === 'GET' && (pathname === '/api/updates/latest' || pathname === '/latest.json')) {
      return await handleManifest(req, res);
    }

    // Public proof of the shipped build: version, build and the post-staple SHA-256.
    if (req.method === 'GET' && pathname === '/release-info.txt') {
      try {
        const raw = await fsp.readFile(path.join(STORAGE_DIR, 'release-info.txt'), 'utf8');
        res.writeHead(200, {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'no-store',
          ...securityHeaders(pathname),
        });
        return res.end(raw);
      } catch {
        return send(res, 404, { error: 'not_found' });
      }
    }
    if (req.method === 'GET' && (pathname === '/checkout/personal' || pathname === '/checkout/pro')) {
      return await handleCheckout(req, res, pathname.endsWith('pro') ? 'pro' : 'personal', url);
    }
    if (req.method === 'POST' && pathname === '/api/webhooks/stripe') return await handleStripeWebhook(req, res);
    if (req.method === 'POST' && pathname === '/api/license/activate') return await handleActivate(req, res);
    if (req.method === 'POST' && pathname === '/api/license/deactivate') return await handleDeactivate(req, res);

    if (pathname === '/api/auth/google') {
      const state = crypto.randomBytes(16).toString('base64url');
      res.writeHead(302, { Location: authUrl(state), 'Set-Cookie': stateCookie(state), 'Cache-Control': 'no-store' });
      return res.end();
    }
    if (pathname === '/api/auth/callback/google') {
      const code = url.searchParams.get('code');
      const state = url.searchParams.get('state');
      const cookieState = readOAuthState(req.headers.cookie);
      const stateMatches = Boolean(state && cookieState)
        && state.length === cookieState.length
        && crypto.timingSafeEqual(Buffer.from(state), Buffer.from(cookieState));
      if (!stateMatches) {
        return send(res, 403, { error: 'invalid_state' }, { 'Set-Cookie': clearStateCookie() });
      }
      if (!code) {
        return send(res, 400, { error: 'missing_code' }, { 'Set-Cookie': clearStateCookie() });
      }
      try {
        const profile = await exchangeCode(code);
        if (!ADMIN_EMAIL.includes(profile.email)) {
          return send(res, 403, { error: 'forbidden' }, { 'Set-Cookie': clearStateCookie() });
        }
        res.writeHead(302, {
          Location: '/admin',
          'Set-Cookie': [sessionCookie(profile.email), clearStateCookie()],
          'Cache-Control': 'no-store',
        });
        return res.end();
      } catch {
        return send(res, 403, { error: 'forbidden' }, { 'Set-Cookie': clearStateCookie() });
      }
    }
    if (pathname === '/api/auth/logout') {
      res.writeHead(302, { Location: '/admin', 'Set-Cookie': clearCookie(), 'Cache-Control': 'no-store' });
      return res.end();
    }

    if (pathname.startsWith('/api/admin/')) {
      const session = adminGate(req, res);
      if (!session) return;
      return await handleAdminApi(req, res, url, session);
    }

    if (pathname === '/admin' || pathname === '/admin/') {
      const session = readSession(req.headers.cookie);
      if (!session) {
        // Fail-closed: 401 with a client-side hand-off to Google OAuth.
        const html = `<!doctype html><meta charset="utf-8">
<meta http-equiv="refresh" content="0;url=/api/auth/google">
<title>TapCopy · Admin</title>
<body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0d0e11;color:#f4f4f5;display:grid;place-items:center;height:100vh;margin:0">
<p>401 · Acceso restringido · <a style="color:#38bdf8" href="/api/auth/google">Entrar con Google</a></p>
</body>`;
        res.writeHead(401, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
          ...securityHeaders('/admin'),
        });
        return res.end(html);
      }
      const html = await fsp.readFile(path.join(ROOT, 'src', 'admin.html'), 'utf8');
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
        ...securityHeaders('/admin'),
      });
      return res.end(html);
    }

    if (req.method === 'GET' || req.method === 'HEAD') {
      // Language negotiation only for real page routes; assets, API and download bypass it.
      if (!pathname.startsWith('/api/') && !pathname.startsWith('/assets/') && !pathname.startsWith('/download')
          && !path.extname(pathname)) {
        const target = resolveRedirect({
          pathname,
          cookie: req.headers.cookie,
          country: req.headers['cf-ipcountry'],
          acceptLanguage: req.headers['accept-language'],
          userAgent: req.headers['user-agent'],
        });
        if (target) {
          res.writeHead(302, {
            Location: target + (url.search || ''),
            'Cache-Control': 'private, no-store',
            Vary: VARY_VALUE,
          });
          return res.end();
        }
      }
      return await serveStatic(req, res, url);
    }

    send(res, 405, { error: 'method_not_allowed' });
  } catch (err) {
    console.error('request error', err?.message);
    if (!res.headersSent) send(res, 500, { error: 'internal_error' });
  }
});

async function main() {
  if (process.env.DATABASE_URL) {
    try {
      await migrate();
      await ensureKeyEncryption();
      console.log('database ready');
    } catch (err) {
      console.error('migration failed', err.message);
    }
  }
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`TapCopy portal ${VERSION} (${BUILD}) on :${PORT}`);
  });
}

main();
