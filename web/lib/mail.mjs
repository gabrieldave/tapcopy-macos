const FROM = process.env.RESEND_FROM || 'TapCopy <tapcopy@iareal.net>';
const REPLY_TO = process.env.RESEND_REPLY_TO || 'tapcopy@iareal.net';

export async function sendMail({ to, subject, html, text }) {
  const key = process.env.RESEND_API_KEY;
  if (!key || !to) return { skipped: true };
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM, reply_to: REPLY_TO, to: [to], subject, html, text }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.error('resend error', res.status, body?.message || '');
    return { ok: false, status: res.status };
  }
  return { ok: true, id: body.id };
}

const shell = (title, body) => `<!doctype html><html><body style="margin:0;background:#0b0b0f;color:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
<div style="max-width:560px;margin:0 auto;padding:32px 24px">
<p style="font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:#a1a1aa;margin:0 0 18px">TapCopy · BLACK EYE</p>
<h1 style="font-size:22px;margin:0 0 16px">${title}</h1>
${body}
<p style="margin-top:28px;font-size:12px;color:#71717a">TapCopy · <a href="https://tapcopy.iareal.net" style="color:#38bdf8;text-decoration:none">tapcopy.iareal.net</a> · tapcopy@iareal.net</p>
</div></body></html>`;

export function welcomeMail(lang, downloadUrl) {
  const en = lang !== 'es';
  return {
    subject: en ? 'Your TapCopy trial starts now' : 'Tu prueba de TapCopy empieza ahora',
    html: shell(
      en ? 'Your 14-day trial is ready' : 'Tu prueba de 14 días está lista',
      en
        ? `<p style="color:#d4d4d8;line-height:1.6">Download TapCopy, drag it to Applications and grant Accessibility. Everything runs on your Mac; only license activation and signed update checks reach our server.</p>
           <p><a href="${downloadUrl}" style="display:inline-block;background:#38bdf8;color:#08121a;padding:12px 20px;border-radius:10px;font-weight:600;text-decoration:none">Download TapCopy</a></p>
           <p style="color:#d4d4d8;line-height:1.6">Personal is $7.99 for 1 Mac · Pro is $14.99 for up to 3 Macs. No subscription.</p>`
        : `<p style="color:#d4d4d8;line-height:1.6">Descarga TapCopy, arrástrala a Aplicaciones y concede Accesibilidad. Todo se ejecuta en tu Mac; solo la activación de licencia y la consulta firmada de actualizaciones llegan a nuestro servidor.</p>
           <p><a href="${downloadUrl}" style="display:inline-block;background:#38bdf8;color:#08121a;padding:12px 20px;border-radius:10px;font-weight:600;text-decoration:none">Descargar TapCopy</a></p>
           <p style="color:#d4d4d8;line-height:1.6">Personal cuesta $7.99 USD para 1 Mac · Pro $14.99 USD hasta 3 Macs. Sin suscripción.</p>`,
    ),
    text: en
      ? `Your TapCopy trial is ready: ${downloadUrl}`
      : `Tu prueba de TapCopy está lista: ${downloadUrl}`,
  };
}

export function receiptMail(lang, { key, plan, seats, amount }) {
  const en = lang !== 'es';
  const masked = key;
  return {
    subject: en ? `TapCopy ${plan} license — your key` : `Licencia ${plan} de TapCopy — tu clave`,
    html: shell(
      en ? 'Thank you for buying TapCopy' : 'Gracias por comprar TapCopy',
      en
        ? `<p style="color:#d4d4d8;line-height:1.6">Plan <b>${plan}</b> · ${seats} Mac${seats > 1 ? 's' : ''} · $${amount} USD (one-time payment).</p>
           <p style="color:#a1a1aa;font-size:12px;margin:18px 0 6px">LICENSE KEY</p>
           <p style="font-family:ui-monospace,Menlo,monospace;font-size:20px;letter-spacing:.08em;background:#18181b;border:1px solid #27272a;border-radius:10px;padding:14px 18px">${masked}</p>
           <p style="color:#d4d4d8;line-height:1.6">Open TapCopy → License… and paste the key. Then download the latest signed build:</p>
           <p><a href="https://tapcopy.iareal.net/download/TapCopy.dmg" style="color:#38bdf8">tapcopy.iareal.net/download/TapCopy.dmg</a></p>`
        : `<p style="color:#d4d4d8;line-height:1.6">Plan <b>${plan}</b> · ${seats} Mac${seats > 1 ? 's' : ''} · $${amount} USD (pago único).</p>
           <p style="color:#a1a1aa;font-size:12px;margin:18px 0 6px">CLAVE DE LICENCIA</p>
           <p style="font-family:ui-monospace,Menlo,monospace;font-size:20px;letter-spacing:.08em;background:#18181b;border:1px solid #27272a;border-radius:10px;padding:14px 18px">${masked}</p>
           <p style="color:#d4d4d8;line-height:1.6">Abre TapCopy → Licencia… y pega la clave. Después descarga la compilación firmada más reciente:</p>
           <p><a href="https://tapcopy.iareal.net/download/TapCopy.dmg" style="color:#38bdf8">tapcopy.iareal.net/download/TapCopy.dmg</a></p>`,
    ),
    text: en
      ? `TapCopy ${plan} license key: ${key}`
      : `Clave de licencia TapCopy ${plan}: ${key}`,
  };
}
