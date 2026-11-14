// Layer 5 + Layer 6 unit tests (no network, no database).
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import {
  clientIp, createRateLimiter, hashLicenseKey, maskKey, RATE_MAX, RATE_WINDOW_MS,
} from '../lib/security.mjs';
import { readOAuthState, clearStateCookie, stateCookie } from '../lib/auth.mjs';

// ---------------------------------------------------------------- limiter ---
test('rate limiter: 10 allowed, 11th blocked with Retry-After', () => {
  const limiter = createRateLimiter({ cleanupMs: 0 });
  for (let i = 1; i <= RATE_MAX; i += 1) {
    assert.equal(limiter.check('1.2.3.4:trial').allowed, true, `attempt ${i}`);
  }
  const verdict = limiter.check('1.2.3.4:trial');
  assert.equal(verdict.allowed, false);
  assert.ok(verdict.retryAfter > 0 && verdict.retryAfter <= RATE_WINDOW_MS / 1000);
  limiter.stop();
});

test('rate limiter: buckets are isolated per IP and per scope', () => {
  const limiter = createRateLimiter({ cleanupMs: 0 });
  for (let i = 0; i < RATE_MAX; i += 1) limiter.check('a:trial');
  assert.equal(limiter.check('a:trial').allowed, false);
  assert.equal(limiter.check('b:trial').allowed, true);
  assert.equal(limiter.check('a:license').allowed, true);
  limiter.stop();
});

test('rate limiter: the window resets and the map is swept', () => {
  let now = 1_000_000;
  const limiter = createRateLimiter({ windowMs: 1000, max: 2, cleanupMs: 0, now: () => now });
  assert.equal(limiter.check('ip').allowed, true);
  assert.equal(limiter.check('ip').allowed, true);
  assert.equal(limiter.check('ip').allowed, false);
  now += 1001;
  assert.equal(limiter.check('ip').allowed, true);
  limiter.stop();
});

test('clientIp prefers CF-Connecting-IP, then X-Forwarded-For', () => {
  assert.equal(clientIp({ headers: { 'cf-connecting-ip': '9.9.9.9' } }), '9.9.9.9');
  assert.equal(clientIp({ headers: { 'x-forwarded-for': '8.8.8.8, 10.0.0.1' } }), '8.8.8.8');
  assert.equal(clientIp({ headers: {}, socket: { remoteAddress: '127.0.0.1' } }), '127.0.0.1');
  assert.equal(clientIp({ headers: {} }), 'unknown');
});

// ------------------------------------------------------- hashing / masking ---
test('hashLicenseKey is SHA-256 of trim+uppercase', () => {
  const key = 'TCOPY-ABCD-EFGH-JKLM';
  const expected = crypto.createHash('sha256').update(key).digest('hex');
  assert.equal(hashLicenseKey('  tcopy-abcd-efgh-jklm  '), expected);
  assert.match(hashLicenseKey(key), /^[a-f0-9]{64}$/);
});

test('maskKey masks once and is idempotent', () => {
  const masked = maskKey('TCOPY-ABCD-EFGH-JKLM');
  assert.equal(masked, 'TCOPY-••••-••••-JKLM');
  assert.equal(maskKey(masked), masked);
  assert.equal(maskKey(''), '');
});

// -------------------------------------------------------------- OAuth state ---
test('readOAuthState parses the CSRF cookie and rejects missing values', () => {
  assert.equal(readOAuthState('a=1; tapcopy_oauth_state=abc123; b=2'), 'abc123');
  assert.equal(readOAuthState('tapcopy_oauth_state='), null);
  assert.equal(readOAuthState('other=1'), null);
  assert.equal(readOAuthState(undefined), null);
});

test('state cookies are HttpOnly, Secure, SameSite=Lax', () => {
  const set = stateCookie('xyz');
  assert.match(set, /^tapcopy_oauth_state=xyz; Path=\/; HttpOnly; Secure; SameSite=Lax; Max-Age=600$/);
  assert.match(clearStateCookie(), /^tapcopy_oauth_state=; Path=\/; HttpOnly; Secure; SameSite=Lax; Max-Age=0$/);
});

// ------------------------------------------ Ed25519 license token (Layer 2) ---
test('license tokens carry a raw 64-byte Ed25519 signature', async () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
  const rawPrivate = Buffer.from(privateKey.export({ format: 'jwk' }).d, 'base64url');
  const rawPublic = Buffer.from(publicKey.export({ format: 'jwk' }).x, 'base64url');
  process.env.TAPCOPY_ED25519_PRIVATE_KEY = rawPrivate.toString('base64');
  process.env.TAPCOPY_ED25519_PUBLIC_KEY = rawPublic.toString('base64');

  const { licenseToken } = await import(`../lib/crypto.mjs?test=${Date.now()}`);
  const token = licenseToken({ key: 'TCOPY-ABCD-EFGH-JKLM', plan: 'personal', seats: 1, deviceId: 'a'.repeat(64) });
  const [payloadB64, signatureB64] = token.split('.');
  const signature = Buffer.from(signatureB64, 'base64url');
  assert.equal(signature.length, 64);

  const payload = Buffer.from(payloadB64, 'base64url');
  assert.equal(crypto.verify(null, payload, publicKey, signature), true);

  const body = JSON.parse(payload.toString('utf8'));
  assert.equal(body.key, 'TCOPY-ABCD-EFGH-JKLM');
  assert.equal(body.deviceId, 'a'.repeat(64));
});
