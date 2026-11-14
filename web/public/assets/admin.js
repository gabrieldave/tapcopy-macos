// TapCopy admin console — vanilla, CSP-safe (no eval, no external origin).
(() => {
  const $ = (sel) => document.querySelector(sel);
  const usd = (cents) => `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} USD`;
  const date = (iso) => new Date(iso).toLocaleString('es-MX', { dateStyle: 'medium', timeStyle: 'short' });

  async function api(path, options) {
    const res = await fetch(path, {
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      ...options,
    });
    if (res.status === 401 || res.status === 403) {
      window.location.href = '/api/auth/google';
      throw new Error('unauthorized');
    }
    return res.json();
  }

  function pill(status) {
    const label = status === 'active' ? 'Activa' : status === 'refunded' ? 'Reembolsada' : 'Revocada';
    return `<span class="pill pill--${status}">${label}</span>`;
  }

  function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  async function load() {
    const [me, stats] = await Promise.all([api('/api/admin/me'), api('/api/admin/stats')]);
    $('#email').textContent = me.email;

    $('#revenue').textContent = usd(stats.revenueCents);
    $('#orders').textContent = `${stats.paidOrders} órdenes pagadas · ${stats.totalOrders} totales`;
    $('#licenses').textContent = String(stats.licenses.total);
    $('#seats').textContent = `${stats.licenses.active} activas · ${stats.seatsUsed} Macs activadas`;
    $('#leads').textContent = String(stats.leads.total);
    $('#leadsWeek').textContent = `${stats.leads.week} en los últimos 7 días`;

    if (stats.manifest) {
      $('#manifestVersion').textContent = `${stats.manifest.version} (${stats.manifest.build})`;
      $('#manifestSha').textContent = (stats.manifest.sha256 || '').slice(0, 24) + '…';
      $('#manifestSha').title = stats.manifest.sha256 || '';
    } else {
      $('#manifestVersion').textContent = 'sin manifiesto';
      $('#manifestSha').textContent = '—';
    }

    $('#licenseRows').innerHTML = stats.recent.length
      ? stats.recent.map((l) => `<tr>
          <td class="mono">${esc(l.maskedKey)}</td>
          <td>${esc(l.plan)}</td>
          <td class="mono">${l.used}/${l.seats}</td>
          <td>${pill(l.status)}</td>
          <td>${esc(l.email || '—')}</td>
          <td>${date(l.created_at)}</td>
          <td><button class="ghost" data-key="${esc(l.maskedKey)}" data-action="resend">Reenviar</button>
              <button class="ghost" data-key="${esc(l.maskedKey)}" data-action="revoke">Revocar</button></td>
        </tr>`).join('')
      : '<tr><td colspan="7" class="muted">Sin licencias todavía.</td></tr>';

    $('#leadRows').innerHTML = stats.leadsList.length
      ? stats.leadsList.map((l) => `<tr>
          <td>${esc(l.email || '—')}</td>
          <td class="mono">${esc(l.lang)}</td>
          <td class="mono">${esc(l.ip_country || '—')}</td>
          <td>${esc(l.source || 'landing')}</td>
          <td>${date(l.created_at)}</td>
        </tr>`).join('')
      : '<tr><td colspan="5" class="muted">Sin leads todavía.</td></tr>';

    return stats;
  }

  // The table only carries masked keys; real keys are required for resend/revoke.
  let cache = [];
  async function refreshWithKeys() {
    const stats = await load();
    cache = stats.recent;
  }

  $('#issue').addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = $('#issueEmail').value.trim();
    const plan = $('#issuePlan').value;
    const out = $('#issueOut');
    out.textContent = 'Emitiendo…';
    try {
      const data = await api('/api/admin/licenses', { method: 'POST', body: JSON.stringify({ email, plan }) });
      out.textContent = `Clave emitida: ${data.key}`;
      await refreshWithKeys();
    } catch {
      out.textContent = 'No se pudo emitir la clave.';
    }
  });

  document.addEventListener('click', async (event) => {
    const button = event.target.closest('button[data-action]');
    if (!button) return;
    const masked = button.getAttribute('data-key');
    const entry = cache.find((l) => l.maskedKey === masked);
    if (!entry) return;
    const action = button.getAttribute('data-action');
    const key = window.prompt('Pega la clave completa (TCOPY-...) para ' + action, '');
    if (!key) return;
    button.disabled = true;
    try {
      if (action === 'resend') await api('/api/admin/resend', { method: 'POST', body: JSON.stringify({ key }) });
      if (action === 'revoke') await api('/api/admin/revoke', { method: 'POST', body: JSON.stringify({ key }) });
      await refreshWithKeys();
    } finally {
      button.disabled = false;
    }
  });

  refreshWithKeys().catch(() => {});
})();
