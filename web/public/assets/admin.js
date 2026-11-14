// TapCopy admin console — vanilla, CSP-safe (no eval, no external origin).
// Every license action is addressed by the PostgreSQL row id: the admin never
// types or even sees a TCOPY-… key unless they press "Copiar".
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
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const error = new Error(data.error || `http_${res.status}`);
      error.code = data.error;
      error.status = res.status;
      throw error;
    }
    return data;
  }

  function pill(status) {
    const label = status === 'active' ? 'Activa' : status === 'refunded' ? 'Reembolsada' : status === 'revoked' ? 'Revocada' : status;
    return `<span class="pill pill--${status}">${label}</span>`;
  }

  function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function flash(text, ok = true) {
    const out = $('#issueOut');
    out.textContent = text;
    out.style.color = ok ? '' : 'var(--bad)';
  }

  let rows = [];

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

    rows = stats.recent;
    renderRows();

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

  function renderRows() {
    $('#licenseRows').innerHTML = rows.length
      ? rows.map((l) => `<tr data-id="${l.id}">
          <td class="mono">${esc(l.maskedKey)}</td>
          <td>${esc(l.plan)}</td>
          <td class="mono">${l.used}/${l.seats}</td>
          <td>${pill(l.status)}</td>
          <td>${esc(l.email || '—')}</td>
          <td>${date(l.created_at)}</td>
          <td class="actions">
            <button class="ghost" data-action="copy" data-id="${l.id}" title="${l.hasCipher ? 'Copia la clave completa' : 'Fila antigua: solo copia desde el registro original'}">Copiar</button>
            <button class="ghost" data-action="resend" data-id="${l.id}" ${l.status === 'refunded' ? 'disabled' : ''}>Reenviar</button>
            ${l.status === 'revoked'
              ? `<button class="ghost" data-action="reactivate" data-id="${l.id}">Reactivar</button>`
              : `<button class="ghost" data-action="revoke" data-id="${l.id}">Revocar</button>`}
            <button class="ghost danger" data-action="delete" data-id="${l.id}">Eliminar</button>
          </td>
        </tr>`).join('')
      : '<tr><td colspan="7" class="muted">Sin licencias todavía.</td></tr>';
  }

  async function copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      const area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      const ok = document.execCommand('copy');
      area.remove();
      return ok;
    }
  }

  $('#issue').addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = $('#issueEmail').value.trim();
    const plan = $('#issuePlan').value;
    flash('Emitiendo…');
    try {
      const data = await api('/api/admin/licenses', { method: 'POST', body: JSON.stringify({ email, plan }) });
      flash(`Clave emitida: ${data.key}`);
      $('#issueEmail').value = '';
      await load();
    } catch {
      flash('No se pudo emitir la clave.', false);
    }
  });

  document.addEventListener('click', async (event) => {
    const button = event.target.closest('button[data-action]');
    if (!button) return;
    const id = Number(button.getAttribute('data-id'));
    const action = button.getAttribute('data-action');
    const row = rows.find((r) => r.id === id);
    if (!row) return;
    button.disabled = true;
    try {
      if (action === 'copy') {
        const data = await api(`/api/admin/licenses/${id}/key`);
        const ok = await copyToClipboard(data.key);
        flash(ok ? `Clave ${data.maskedKey} copiada al portapapeles.` : `No se pudo copiar ${data.maskedKey}.`, ok);
      }

      if (action === 'resend') {
        let email = row.email || '';
        if (!email) {
          email = window.prompt('Esta fila no tiene correo. ¿A qué dirección envío la clave?', '') || '';
          if (!email.includes('@')) {
            flash('Correo cancelado o inválido; no se envió nada.', false);
            return;
          }
        } else if (!window.confirm(`¿Reenviar la clave ${row.maskedKey} a ${email}?`)) {
          return;
        }
        const data = await api(`/api/admin/licenses/${id}/resend`, {
          method: 'POST',
          body: JSON.stringify({ email }),
        });
        flash(`Clave ${row.maskedKey} reenviada a ${data.to}.`);
        await load();
      }

      if (action === 'revoke') {
        if (!window.confirm(`¿Revocar la licencia ${row.maskedKey}? La app dejará de aceptarla.`)) return;
        await api(`/api/admin/licenses/${id}/revoke`, { method: 'POST' });
        flash(`Licencia ${row.maskedKey} revocada.`);
        await load();
      }

      if (action === 'reactivate') {
        if (!window.confirm(`¿Reactivar la licencia ${row.maskedKey}?`)) return;
        await api(`/api/admin/licenses/${id}/reactivate`, { method: 'POST' });
        flash(`Licencia ${row.maskedKey} reactivada.`);
        await load();
      }

      if (action === 'delete') {
        if (!window.confirm(`¿Eliminar definitivamente ${row.maskedKey} y sus asientos? Esta acción no se puede deshacer.`)) return;
        await api(`/api/admin/licenses/${id}`, { method: 'DELETE' });
        flash(`Licencia ${row.maskedKey} eliminada.`);
        await load();
      }
    } catch (error) {
      if (error.code === 'no_key_stored') {
        flash('Fila antigua sin copia cifrada guardada: no hay clave recuperable.', false);
      } else if (error.code === 'email_required') {
        flash('Esa fila necesita un correo destino.', false);
      } else if (error.code === 'mail_failed') {
        flash('Resend rechazó el envío; revisa el correo destino.', false);
      } else if (error.message !== 'unauthorized') {
        flash(`No se pudo completar la acción (${error.code || error.status || 'error'}).`, false);
      }
    } finally {
      button.disabled = false;
    }
  });

  load().catch(() => {});
})();
