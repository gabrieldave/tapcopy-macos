import crypto from 'node:crypto';

export const ADMIN_EMAIL = (process.env.ADMIN_ALLOWED_EMAILS || 'david.del.rio.colin@gmail.com')
  .split(',')
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);

export const CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET || '';
const SECRET = process.env.SESSION_SECRET || process.env.TAPCOPY_SESSION_SECRET || '';
export const CALLBACK = 'https://tapcopy.iareal.net/api/auth/callback/google';
const COOKIE = 'tapcopy_admin';
const MAX_AGE = 60 * 60 * 8;

const b64 = (buf) => Buffer.from(buf).toString('base64url');

function sign(value) {
  return crypto.createHmac('sha256', SECRET).update(value).digest('base64url');
}

export function makeSession(email) {
  const payload = b64(JSON.stringify({ email, exp: Date.now() + MAX_AGE * 1000 }));
  return `${payload}.${sign(payload)}`;
}

export function readSession(cookieHeader) {
  if (!cookieHeader || !SECRET) return null;
  const raw = cookieHeader
    .split(';')
    .map((p) => p.trim())
    .find((p) => p.startsWith(`${COOKIE}=`));
  if (!raw) return null;
  const token = raw.slice(COOKIE.length + 1);
  const [payload, sig] = token.split('.');
  if (!payload || !sig) return null;
  const expected = sign(payload);
  if (expected.length !== sig.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(sig))) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!data.exp || data.exp < Date.now()) return null;
    if (!ADMIN_EMAIL.includes(String(data.email).toLowerCase())) return null;
    return { email: String(data.email).toLowerCase() };
  } catch {
    return null;
  }
}

export function sessionCookie(email) {
  return `${COOKIE}=${makeSession(email)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${MAX_AGE}`;
}

export function clearCookie() {
  return `${COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

export function authUrl(state) {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: CALLBACK,
    response_type: 'code',
    scope: 'openid email profile',
    access_type: 'online',
    prompt: 'select_account',
    state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

export async function exchangeCode(code) {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: CALLBACK,
      grant_type: 'authorization_code',
    }),
  });
  const tokens = await res.json();
  if (!res.ok || !tokens.access_token) throw new Error('oauth_exchange_failed');
  const info = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });
  const profile = await info.json();
  if (!profile?.email || profile.email_verified === false) throw new Error('email_not_verified');
  return { email: String(profile.email).toLowerCase(), name: profile.name || '' };
}

const STATE_COOKIE = 'tapcopy_oauth_state';

/** Reads the short-lived CSRF state cookie set by /api/auth/google. */
export function readOAuthState(cookieHeader) {
  if (!cookieHeader) return null;
  const raw = String(cookieHeader)
    .split(';')
    .map((part) => part.trim())
    .find((part) => part.startsWith(`${STATE_COOKIE}=`));
  if (!raw) return null;
  const value = raw.slice(STATE_COOKIE.length + 1);
  return value || null;
}

/** Expires the state cookie (also sent after a successful exchange). */
export function clearStateCookie() {
  return `${STATE_COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

export const stateCookie = (state) =>
  `${STATE_COOKIE}=${state}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=600`;
