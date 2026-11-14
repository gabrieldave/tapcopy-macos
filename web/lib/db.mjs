import { Pool } from 'pg';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 6,
  idleTimeoutMillis: 30_000,
  ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
});

export const db = {
  query: (text, params) => pool.query(text, params),
  pool,
};

export async function migrate() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS trial_leads (
      id BIGSERIAL PRIMARY KEY,
      email TEXT,
      lang TEXT NOT NULL DEFAULT 'en',
      ip_country TEXT,
      source TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS orders (
      id BIGSERIAL PRIMARY KEY,
      stripe_session_id TEXT UNIQUE,
      stripe_payment_intent TEXT,
      email TEXT,
      plan TEXT NOT NULL,
      seats INT NOT NULL,
      amount_cents INT NOT NULL,
      currency TEXT NOT NULL DEFAULT 'usd',
      lang TEXT NOT NULL DEFAULT 'en',
      status TEXT NOT NULL DEFAULT 'paid',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS licenses (
      id BIGSERIAL PRIMARY KEY,
      key TEXT UNIQUE NOT NULL,
      plan TEXT NOT NULL,
      seats INT NOT NULL,
      email TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      order_id BIGINT REFERENCES orders(id) ON DELETE SET NULL,
      issued_by TEXT NOT NULL DEFAULT 'stripe',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      revoked_at TIMESTAMPTZ,
      refunded_at TIMESTAMPTZ
    );

    CREATE TABLE IF NOT EXISTS license_activations (
      id BIGSERIAL PRIMARY KEY,
      license_id BIGINT NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
      device_id TEXT NOT NULL,
      mac_name TEXT,
      first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
      last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (license_id, device_id)
    );

    CREATE TABLE IF NOT EXISTS admin_audit (
      id BIGSERIAL PRIMARY KEY,
      email TEXT,
      action TEXT NOT NULL,
      detail TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_activations_license ON license_activations (license_id);
    CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses (status);
  `);
}

export async function dbHealthy() {
  try {
    await pool.query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}
