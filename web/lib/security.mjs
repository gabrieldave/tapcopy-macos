// TapCopy · shared security primitives (Layer 5 + Layer 6).
// Zero external dependencies: Node's crypto only.

import crypto from 'node:crypto';

export const RATE_WINDOW_MS = 900_000; // 15 minutes
export const RATE_MAX = 10;
export const RATE_CLEANUP_MS = 300_000; // sweep every 5 minutes

/** Real client IP behind Cloudflare / Coolify's reverse proxy. */
export function clientIp(req) {
  const cf = req.headers['cf-connecting-ip'];
  if (cf) return String(cf).split(',')[0].trim();
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) return String(forwarded).split(',')[0].trim();
  return req.socket?.remoteAddress || 'unknown';
}

/**
 * Fixed-window in-memory limiter keyed by `ip:bucket`. The Map is swept every
 * 5 minutes so it never grows without bound. `now` is injectable for tests.
 */
export function createRateLimiter({
  windowMs = RATE_WINDOW_MS,
  max = RATE_MAX,
  cleanupMs = RATE_CLEANUP_MS,
  now = () => Date.now(),
} = {}) {
  const buckets = new Map();
  let sweeper = null;

  if (cleanupMs > 0) {
    sweeper = setInterval(() => {
      const current = now();
      for (const [key, entry] of buckets) {
        if (current - entry.start >= windowMs) buckets.delete(key);
      }
    }, cleanupMs);
    if (typeof sweeper.unref === 'function') sweeper.unref();
  }

  return {
    check(key) {
      const current = now();
      let entry = buckets.get(key);
      if (!entry || current - entry.start >= windowMs) {
        entry = { start: current, count: 0 };
        buckets.set(key, entry);
      }
      entry.count += 1;
      if (entry.count > max) {
        return {
          allowed: false,
          retryAfter: Math.max(1, Math.ceil((entry.start + windowMs - current) / 1000)),
        };
      }
      return { allowed: true, retryAfter: 0 };
    },
    reset() {
      buckets.clear();
    },
    stop() {
      if (sweeper) clearInterval(sweeper);
      sweeper = null;
    },
    get size() {
      return buckets.size;
    },
  };
}

/** Process-wide limiter used by the HTTP server. */
export const rateLimiter = createRateLimiter();

/** SHA-256 fingerprint of a license key (trimmed, uppercased). */
export function hashLicenseKey(key) {
  return crypto.createHash('sha256').update(String(key).trim().toUpperCase()).digest('hex');
}

/** Display-safe key. Already-masked values are returned untouched (idempotent). */
export function maskKey(key) {
  const value = String(key || '');
  if (!value || value.includes('••••')) return value;
  if (value.length < 12) return value;
  return `${value.slice(0, 6)}••••-••••-${value.slice(-4)}`;
}
