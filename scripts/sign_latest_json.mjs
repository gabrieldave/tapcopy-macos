#!/usr/bin/env node
// Builds the signed auto-update manifest consumed by AppUpdateChecker.swift.
//
// Usage:
//   TAPCOPY_ED25519_PRIVATE_KEY=<base64 raw 32B> node scripts/sign_latest_json.mjs \
//     --version 1.1.0 --build 5 --dmg dist/TapCopy-1.1.0.dmg --out dist/latest.json
//
// The signature covers `version|build|sha256|url` exactly (base64 Ed25519), which is
// what the app verifies with the public key embedded in LicenseManager.swift.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, arr) => {
    if (cur.startsWith('--')) acc.push([cur.slice(2), arr[i + 1]]);
    return acc;
  }, []),
);

const version = args.version;
const build = Number(args.build);
const dmg = args.dmg;
const out = args.out || 'dist/latest.json';
const url = args.url || 'https://tapcopy.iareal.net/download/TapCopy.dmg';
const minimumSystemVersion = args.minSystem || '14.0';

if (!version || !build || !dmg) {
  console.error('usage: --version X.Y.Z --build N --dmg path [--out path] [--url url]');
  process.exit(1);
}

const raw = Buffer.from(process.env.TAPCOPY_ED25519_PRIVATE_KEY || '', 'base64');
if (raw.length !== 32) {
  console.error('TAPCOPY_ED25519_PRIVATE_KEY must be a base64 raw 32-byte Ed25519 key');
  process.exit(1);
}

const key = crypto.createPrivateKey({
  key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), raw]),
  format: 'der',
  type: 'pkcs8',
});

const sha256 = crypto.createHash('sha256').update(fs.readFileSync(dmg)).digest('hex');
const payload = `${version}|${build}|${sha256}|${url}`;
const signature = crypto.sign(null, Buffer.from(payload), key).toString('base64');

const manifest = {
  version,
  build,
  url,
  sha256,
  publishedAt: new Date().toISOString(),
  minimumSystemVersion,
  edSignature: signature,
};

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify(manifest, null, 2));
