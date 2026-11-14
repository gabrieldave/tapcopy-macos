import crypto from 'node:crypto';

const API = 'https://api.stripe.com/v1';
const KEY = process.env.STRIPE_SECRET_KEY;

export const PLANS = {
  personal: { seats: 1, amountCents: 799, label: 'TapCopy Personal — 1 Mac' },
  pro: { seats: 3, amountCents: 1499, label: 'TapCopy Pro — up to 3 Macs' },
};

async function stripe(path, body) {
  if (!KEY) throw new Error('stripe_not_configured');
  const res = await fetch(`${API}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(body).toString(),
  });
  const json = await res.json();
  if (!res.ok) {
    const err = new Error(json?.error?.message || 'stripe_error');
    err.stripe = json?.error;
    throw err;
  }
  return json;
}

export async function createCheckout({ plan, lang, origin }) {
  const cfg = PLANS[plan];
  if (!cfg) throw new Error('unknown_plan');
  const params = {
    mode: 'payment',
    'payment_method_types[0]': 'card',
    // Currency is declared once; currency_options must not be duplicated for usd.
    'line_items[0][quantity]': '1',
    'line_items[0][price_data][currency]': 'usd',
    'line_items[0][price_data][unit_amount]': String(cfg.amountCents),
    'line_items[0][price_data][product_data][name]': cfg.label,
    'metadata[app]': 'tapcopy',
    'metadata[plan]': plan,
    'metadata[seats]': String(cfg.seats),
    'metadata[lang]': lang,
    'payment_intent_data[metadata][app]': 'tapcopy',
    'payment_intent_data[metadata][plan]': plan,
    'payment_intent_data[metadata][seats]': String(cfg.seats),
    'payment_intent_data[description]': cfg.label,
    success_url: `${origin}/?paid=1&lang=${lang}`,
    cancel_url: `${origin}/?canceled=1&lang=${lang}`,
    allow_promotion_codes: 'true',
    billing_address_collection: 'auto',
  };
  const session = await stripe('/checkout/sessions', params);
  return session;
}

export function verifyWebhook(rawBody, signatureHeader) {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) return { ok: false, reason: 'webhook_not_configured' };
  if (!signatureHeader) return { ok: false, reason: 'missing_signature' };

  const parts = Object.fromEntries(
    signatureHeader.split(',').map((p) => {
      const [k, v] = p.split('=');
      return [k, v];
    }),
  );
  const timestamp = Number(parts.t);
  if (!timestamp || Math.abs(Date.now() / 1000 - timestamp) > 300) {
    return { ok: false, reason: 'stale_timestamp' };
  }
  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${parts.t}.${rawBody}`)
    .digest('hex');
  const provided = parts.v1 || '';
  if (provided.length !== expected.length) return { ok: false, reason: 'bad_signature' };
  if (!crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(provided))) {
    return { ok: false, reason: 'bad_signature' };
  }
  return { ok: true, event: JSON.parse(rawBody) };
}

// Best-effort coordination with the BLACK EYE payment bus; never blocks the purchase.
export function notifyN8n(payload) {
  const url = process.env.N8N_PAYMENT_WEBHOOK;
  if (!url) return;
  Promise.resolve()
    .then(() =>
      fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      }),
    )
    .catch(() => {});
}
