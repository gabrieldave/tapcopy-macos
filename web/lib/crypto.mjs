import crypto from 'node:crypto';

function rawKey(value) {
  const buf = Buffer.from(value || '', 'base64');
  if (buf.length !== 32) throw new Error('Ed25519 key must be 32 raw bytes (base64)');
  return buf;
}

export const privateKey = rawKey(process.env.TAPCOPY_ED25519_PRIVATE_KEY);
export const publicKey = rawKey(process.env.TAPCOPY_ED25519_PUBLIC_KEY);

const PRIV = crypto.createPrivateKey({
  key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), privateKey]),
  format: 'der',
  type: 'pkcs8',
});

export function sign(payload) {
  return crypto.sign(null, Buffer.from(payload), PRIV).toString('base64');
}

/// Raw 64-byte signature, encoded once as base64url (what CryptoKit expects on
/// `publicKey.isValidSignature(signature, for: payloadBytes)`).
export function signBase64URL(payload) {
  return crypto.sign(null, Buffer.from(payload), PRIV).toString('base64url');
}

export function verify(payload, signature) {
  const key = crypto.createPublicKey({
    key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), publicKey]),
    format: 'der',
    type: 'spki',
  });
  try {
    return crypto.verify(null, Buffer.from(payload), key, Buffer.from(signature, 'base64'));
  } catch {
    return false;
  }
}

export function licenseToken({ key, plan, seats, deviceId }) {
  const body = { v: 1, key, plan, seats, deviceId, iat: Math.floor(Date.now() / 1000) };
  const json = Buffer.from(JSON.stringify(body)).toString('base64url');
  // NOTE: the signature must be the raw 64 Ed25519 bytes, base64url-encoded ONCE.
  // `Buffer.from(sign(json)).toString('base64url')` double-encodes the base64 text
  // (88 bytes) and CryptoKit silently rejects it.
  return `${json}.${signBase64URL(json)}`;
}

export function updateManifestSignature({ version, build, sha256, url }) {
  return sign(`${version}|${build}|${sha256}|${url}`);
}
