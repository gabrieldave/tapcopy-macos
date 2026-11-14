/* TapCopy · WEB_FACTORY · site runtime (vanilla, CSP-safe: no eval, no inline handlers). */
(() => {
  'use strict';
  const root = document.documentElement;
  root.classList.add('js');
  const $ = (s, c = document) => c.querySelector(s);
  const $$ = (s, c = document) => Array.from(c.querySelectorAll(s));
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let T = {};
  try { T = JSON.parse($('#i18n')?.textContent || '{}'); } catch (_) { /* keep defaults */ }

  /* ---------------- Language switch: manual cookie, 1 year ---------------- */
  $$('[data-set-lang]').forEach((a) => a.addEventListener('click', () => {
    const lang = a.getAttribute('data-set-lang');
    const secure = location.protocol === 'https:' ? '; Secure' : '';
    document.cookie = `tapcopy-lang=${lang}; Max-Age=31536000; Path=/; SameSite=Lax${secure}`;
    if (location.hash && !a.hash && document.getElementById(location.hash.slice(1))) a.hash = location.hash;
  }));

  /* ---------------- Reveal + counters ---------------- */
  const fmt = (v, d, prefix = '') => prefix + v.toFixed(d);
  function count(el) {
    const target = parseFloat(el.dataset.count);
    const decimals = parseInt(el.dataset.decimals || '0', 10);
    const prefix = el.dataset.prefix || '';
    if (!target || reduced) { el.textContent = fmt(target || 0, decimals, prefix); return; }
    const t0 = performance.now(); const dur = 1100;
    const tick = (now) => {
      const k = Math.min(1, (now - t0) / dur);
      const e = 1 - Math.pow(1 - k, 3);
      el.textContent = fmt(target * e, decimals, prefix);
      if (k < 1) requestAnimationFrame(tick); else el.textContent = fmt(target, decimals, prefix);
    };
    requestAnimationFrame(tick);
  }
  const io = new IntersectionObserver((entries) => entries.forEach((en) => {
    if (!en.isIntersecting) return;
    en.target.classList.add('is-visible');
    $$('[data-count]', en.target).forEach(count);
    if (en.target.matches('[data-count]')) count(en.target);
    io.unobserve(en.target);
  }), { threshold: 0.18, rootMargin: '0px 0px -40px 0px' });
  $$('[data-reveal]').forEach((el) => io.observe(el));

  /* ---------------- Kinetic headline + case ticker ---------------- */
  const morph = $('[data-morph]');
  if (morph && !reduced) { let s = 0; setInterval(() => { s = (s + 1) % 4; morph.dataset.state = String(s); }, 1700); }

  /* ---------------- Chameleon analyzer (port of ChameleonAnalyzer.swift) ---------------- */
  const Analyzer = {
    detect(raw) {
      const t = raw.trim();
      if (!t || t.length > 1024 || /[\r\n]/.test(t)) return null;
      return this.color(t) || this.url(t) || this.math(t);
    },
    color(t) {
      const m = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(t);
      if (m) {
        let h = m[1];
        if (h.length === 3) h = h.split('').map((c) => c + c).join('');
        const v = parseInt(h.slice(0, 6), 16);
        const r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
        const conv = h.length === 8 ? `rgba(${r}, ${g}, ${b}, ${(parseInt(h.slice(6), 16) / 255).toFixed(2)})` : `rgb(${r}, ${g}, ${b})`;
        return { type: 'color', swatch: `#${h.slice(0, 6)}`, value: conv, badge: 'RGB' };
      }
      const c = /^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*([\d.]+)\s*)?\)$/i.exec(t);
      if (c && [c[1], c[2], c[3]].every((n) => +n <= 255)) {
        const hex = '#' + [c[1], c[2], c[3]].map((n) => (+n).toString(16).padStart(2, '0')).join('').toUpperCase();
        return { type: 'color', swatch: hex, value: hex, badge: hex };
      }
      return null;
    },
    url(t) {
      if (/\s/.test(t)) return null;
      if (/^https?:\/\/[^/\s]+/i.test(t)) return { type: 'url', value: t };
      if (/^(?:[a-zA-Z0-9-]+\.)+([a-zA-Z]{2,12})(?:\/\S*)?$/.test(t)) return { type: 'url', value: 'https://' + t };
      return null;
    },
    math(t) {
      if (t.length > 80) return null;
      if (/^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$/.test(t) || /^\+\d[\d\s-]{6,}$/.test(t)) return null;
      const s = t.replace(/×/g, '*').replace(/÷/g, '/').replace(/[$,]/g, '').replace(/^[\s=?]+|[\s=?]+$/g, '');
      if (!s || !/^[0-9.+\-*/%() ]+$/.test(s)) return null;
      const src = s.replace(/ /g, ''); let pos = 0; let ops = 0;
      const peek = () => src[pos];
      const num = () => { const m = /^\d*\.?\d+|^\d+\./.exec(src.slice(pos)); if (!m) return null; pos += m[0].length; return parseFloat(m[0]); };
      const factor = () => {
        if (peek() === '+') { pos++; return factor(); }
        if (peek() === '-') { pos++; const v = factor(); return v == null ? null : -v; }
        if (peek() === '(') { pos++; const v = expr(); if (v == null || peek() !== ')') return null; pos++; return v; }
        return num();
      };
      const term = () => {
        let l = factor(); if (l == null) return null;
        while ('*/%'.includes(peek() || '_')) {
          const op = src[pos++]; const r = factor(); if (r == null) return null; ops++;
          if (op === '*') l *= r; else { if (Math.abs(r) < 1e-12) return null; l = op === '/' ? l / r : l % r; }
        }
        return l;
      };
      const expr = () => {
        let l = term(); if (l == null) return null;
        while (peek() === '+' || peek() === '-') { const op = src[pos++]; const r = term(); if (r == null) return null; ops++; l = op === '+' ? l + r : l - r; }
        return l;
      };
      const v = expr();
      if (v == null || pos !== src.length || ops === 0 || !Number.isFinite(v)) return null;
      const out = Math.abs(Math.round(v) - v) < 1e-9 && Math.abs(v) < 1e15 ? String(Math.round(v)) : v.toFixed(4).replace(/\.?0+$/, '');
      return { type: 'math', value: out };
    },
    words(t) { return t.match(/[\p{L}\p{N}]+/gu) || []; },
    transform(t, kind) {
      const w = this.words(t);
      const cap = (x) => x.charAt(0).toLocaleUpperCase() + x.slice(1).toLocaleLowerCase();
      switch (kind) {
        case 'upper': return t.toLocaleUpperCase();
        case 'lower': return t.toLocaleLowerCase();
        case 'title': return t.replace(/[\p{L}\p{N}]+/gu, cap);
        case 'snake': return w.map((x) => x.toLocaleLowerCase()).join('_');
        case 'camel': return w.map((x, i) => (i ? cap(x) : x.toLocaleLowerCase())).join('');
        case 'markdown': return '```\n' + t + '\n```';
        default: return t;
      }
    },
    stats(t) {
      const s = t.trim();
      return { w: s ? s.split(/\s+/).length : 0, c: Array.from(s).length };
    },
  };

  const ticker = $('[data-case-ticker]');
  if (ticker && !reduced) {
    const base = 'launch checklist'; const kinds = ['snake', 'camel', 'upper', 'title'];
    let i = 0;
    setInterval(() => { i = (i + 1) % kinds.length; ticker.style.opacity = '0'; setTimeout(() => { ticker.textContent = Analyzer.transform(base, kinds[i]); ticker.style.opacity = '1'; }, 200); }, 1800);
  }

  /* ---------------- Live hero stage ---------------- */
  const stage = $('#stage');
  if (stage) initStage();

  function initStage() {
    const doc = $('#doc'), pill = $('#pill'), chip = $('#aiChip'), ghost = $('#ghostSlot');
    const menu = $('#aaMenu'), toastEl = $('#toast'), shelf = $('#shelf'), shelfEmpty = $('#shelfEmpty');
    const hudStatus = $('#hudStatus'), hudLed = $('#hudLed'), hudXY = $('#hudXY');
    const P = T.pill || {}, H = T.hero || {};
    const BAR = 34, GAP = 12, MARGIN = 10, EDGE = 8, MAX_PINS = 4;
    const ICON = {
      copy: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="5" y="5" width="8.5" height="9" rx="1.8"/><path d="M3.5 10.5V3.8c0-1 .8-1.8 1.8-1.8h5"/></svg>',
      open: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="2.5" y="2.5" width="11" height="11" rx="2.4"/><path d="M6.5 9.5l4-4M7 5.5h3.5V9"/></svg>',
      search: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="7" cy="7" r="4.3"/><path d="M10.2 10.2l3.3 3.3"/></svg>',
      pin: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M6 2.5h4l-.6 4 2.6 2.3H4l2.6-2.3z"/><path d="M8 8.8v4.7"/></svg>',
    };
    let current = null; let hideTimer = 0; let chipSide = 0; let hovering = false;
    let attract = !reduced; let attractTimer = 0; let attractIdx = 0;
    const pins = [];

    const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const sRect = () => stage.getBoundingClientRect();
    const rel = (r) => { const s = sRect(); return { x: r.left - s.left, y: r.top - s.top, w: r.width, h: r.height }; };
    const hit = (a, b) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
    const inflate = (r, m) => ({ x: r.x - m, y: r.y - m, w: r.w + 2 * m, h: r.h + 2 * m });
    const pad3 = (n) => String(Math.max(0, Math.round(n))).padStart(3, '0');

    function toast(msg) {
      toastEl.textContent = msg; toastEl.classList.add('is-on');
      clearTimeout(toast.t); toast.t = setTimeout(() => toastEl.classList.remove('is-on'), 2200);
    }
    function copy(text) {
      if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).catch(() => {});
    }
    function hud(state, text) {
      hudStatus.textContent = text;
      hudLed.className = 'hud__led' + (state ? ` is-${state}` : '');
    }

    function segmentsFor(text, match) {
      const segs = [{ id: 'copy', html: ICON.copy + esc(P.copy) }];
      let hideSearch = false;
      if (match?.type === 'url') { segs.push({ id: 'open', cls: 'seg--accent', html: ICON.open + esc(P.open) }); hideSearch = true; }
      if (match?.type === 'color') { segs.push({ id: 'color', html: `<span class="seg__sw" style="background:${match.swatch}"></span>${esc(match.badge)}` }); hideSearch = true; }
      if (match?.type === 'math') segs.push({ id: 'math', cls: 'seg--accent', html: '= ' + esc(match.value) });
      segs.push({ id: 'plain', html: esc(P.plain) });
      segs.push({ id: 'aa', html: 'Aa', aria: P.transform });
      if (!hideSearch) segs.push({ id: 'search', html: ICON.search, aria: P.searchAria });
      segs.push({ id: 'pin', html: ICON.pin, aria: P.pinAria });
      return segs.map((s, i) => (i ? '<span class="div"></span>' : '') +
        `<button type="button" class="seg ${s.cls || ''}" data-act="${s.id}"${s.aria ? ` aria-label="${esc(s.aria)}"` : ''}>${s.html}</button>`).join('');
    }

    function setPillContent(html) {
      const wasHidden = pill.hidden;
      const from = wasHidden ? 0 : pill.offsetWidth;
      pill.style.transition = 'none';
      pill.style.width = 'max-content'; // measure free of the containing block's right edge
      pill.innerHTML = html;
      const to = pill.offsetWidth + 1; // offsetWidth ignores the entry scale transform
      pill.style.width = (!wasHidden && from && !reduced ? from : to) + 'px';
      void pill.offsetWidth;
      pill.style.transition = '';
      pill.style.width = to + 'px';
      return to;
    }

    function place(sel, pillW) {
      const s = sRect();
      const W = s.width, Hs = s.height;
      // Simulated floating AI button: alternates between a toolbar above the selection
      // (Notion / Medium style) and a chip below it (Gemini style).
      chipSide = (chipSide + 1) % 2;
      const chipW = chip.offsetWidth || 150, chipH = 36;
      const chipBox = {
        x: Math.min(Math.max(EDGE, sel.x), W - chipW - EDGE),
        y: chipSide ? sel.y - chipH - 10 : sel.y + sel.h + 8,
        w: chipW, h: chipH,
      };
      if (chipBox.y < EDGE) chipBox.y = sel.y + sel.h + 8;
      chip.style.left = chipBox.x + 'px'; chip.style.top = chipBox.y + 'px';
      chip.classList.add('is-on');

      const obstacles = [inflate(chipBox, MARGIN), sel];
      const clampX = (x) => Math.min(Math.max(EDGE, x), W - pillW - EDGE);
      const cands = [
        { x: sel.x, y: sel.y - BAR - GAP },            // 1 above-right
        { x: sel.x, y: sel.y + sel.h + GAP },          // 2 below-right
        { x: sel.x, y: sel.y + sel.h + 62 },           // 3 further below
        { x: sel.x, y: sel.y - BAR - 58 },             // 4 higher above
        { x: sel.x - pillW * 0.6, y: sel.y - BAR - GAP }, // 5 above-left
        { x: sel.x - pillW * 0.6, y: sel.y + sel.h + GAP }, // 6 below-left
      ].map((c) => ({ x: clampX(c.x), y: c.y, w: pillW, h: BAR }));
      const valid = (c) => c.y >= EDGE && c.y + BAR <= Hs - EDGE && !obstacles.some((o) => hit(c, o));
      const pick = cands.find(valid) || cands[1];
      const dodged = pick !== cands[0] && hit(cands[0], obstacles[0]);
      if (dodged) {
        Object.assign(ghost.style, { left: cands[0].x + 'px', top: cands[0].y + 'px', width: pillW + 'px', height: BAR + 'px' });
        ghost.classList.remove('is-on'); void ghost.offsetWidth; ghost.classList.add('is-on');
        hud('avoid', H.statusAvoid);
      } else {
        ghost.classList.remove('is-on');
        hud('ok', H.statusClear);
      }
      hudXY.textContent = `x ${pad3(pick.x)} · y ${pad3(pick.y)}`;
      return pick;
    }

    function show(text, rect, opts = {}) {
      const clean = text.replace(/\s+/g, ' ').trim();
      if (!clean) return;
      closeMenu();
      const match = Analyzer.detect(clean);
      current = { text: clean, match, demo: !!opts.demo };
      const wasHidden = pill.hidden;
      if (wasHidden) { pill.style.transition = 'none'; pill.hidden = false; pill.classList.add('is-entering'); }
      const w = setPillContent(segmentsFor(clean, match));
      const pos = place(rel(rect), w);
      if (wasHidden) pill.style.transition = 'none';
      pill.style.left = pos.x + 'px'; pill.style.top = pos.y + 'px';
      if (wasHidden) {
        void pill.offsetWidth; pill.style.transition = '';
        requestAnimationFrame(() => pill.classList.remove('is-entering'));
      }
      armHide(5000);
    }

    function hide() {
      clearTimeout(hideTimer); closeMenu();
      pill.hidden = true; chip.classList.remove('is-on'); ghost.classList.remove('is-on');
      $$('.tok.is-sel', doc).forEach((t) => t.classList.remove('is-sel'));
      current = null;
    }
    function armHide(ms) {
      clearTimeout(hideTimer);
      hideTimer = setTimeout(() => { if (hovering && !current?.demo) armHide(1500); else hide(); }, ms);
    }
    function success(msg) {
      setPillContent(`<span class="seg seg--success" role="status">✓ ${esc(msg)}</span>`);
      chip.classList.remove('is-on');
      armHide(900);
    }

    /* ---- Aa transform menu ---- */
    function openMenu(anchor) {
      const st = Analyzer.stats(current.text);
      const items = ['upper', 'lower', 'title', 'snake', 'camel', 'markdown'];
      menu.innerHTML = `<div class="aa-menu__stats">${esc((P.stats || '{w} · {c}').replace('{w}', st.w).replace('{c}', st.c))}</div>` +
        items.map((k) => `<button type="button" role="menuitem" data-tf="${k}">${esc(P[k])}</button>`).join('');
      menu.hidden = false;
      const s = sRect(), a = anchor.getBoundingClientRect(), mh = menu.offsetHeight, mw = menu.offsetWidth;
      let top = a.bottom - s.top + 6; if (top + mh > s.height - EDGE) top = a.top - s.top - mh - 6;
      menu.style.left = Math.min(a.left - s.left, s.width - mw - EDGE) + 'px';
      menu.style.top = Math.max(EDGE, top) + 'px';
      menu.querySelector('button')?.focus({ preventScroll: true });
      armHide(8000);
    }
    function closeMenu() { menu.hidden = true; }

    /* ---- Pin shelf (max 4, fifth replaces the oldest — PinShelfController.maxPins) ---- */
    function layoutShelf() {
      const sr = rel(shelf.getBoundingClientRect());
      const docked = pins.filter((p) => !p.moved);
      shelfEmpty.hidden = pins.length > 0;
      const head = (shelf.querySelector('.shelf__label')?.offsetHeight || 14) + 20;
      shelf.style.minHeight = pins.length ? `${head + docked.length * 82}px` : '';
      const sr2 = rel(shelf.getBoundingClientRect());
      docked.forEach((p, i) => { p.el.style.left = (sr2.x + 8) + 'px'; p.el.style.top = (sr2.y + head + i * 82) + 'px'; });
      return sr;
    }
    function addPin(text) {
      if (pins.length >= MAX_PINS) removePin(pins[0]);
      const el = document.createElement('div');
      el.className = 'pin-card';
      const time = new Date().toLocaleTimeString(T.lang === 'es' ? 'es-MX' : 'en-US', { hour: '2-digit', minute: '2-digit' });
      el.innerHTML = `<div class="pin-card__top"><span class="pin-card__badge">📌 ${esc(P.pinned)} · <span class="num">${esc(time)}</span></span>` +
        `<button type="button" class="pin-card__btn" data-pin="copy">${esc(P.copyPin)}</button>` +
        `<button type="button" class="pin-card__btn pin-card__btn--x" data-pin="close" aria-label="${esc(P.closePin)}">✕</button></div>` +
        `<p class="pin-card__text">${esc(text)}</p>`;
      const pin = { el, text, moved: false };
      pins.push(pin); stage.appendChild(el);
      el.addEventListener('click', (e) => {
        const b = e.target.closest('[data-pin]'); if (!b) return;
        if (b.dataset.pin === 'close') removePin(pin);
        else { copy(text); b.textContent = '✓'; b.classList.add('is-done'); setTimeout(() => { b.textContent = P.copyPin; b.classList.remove('is-done'); }, 1200); }
      });
      drag(pin);
      layoutShelf();
    }
    function removePin(pin) {
      const i = pins.indexOf(pin); if (i < 0) return;
      pins.splice(i, 1); pin.el.remove(); layoutShelf();
    }
    function drag(pin) {
      const el = pin.el; let ox = 0, oy = 0, id = null;
      el.addEventListener('pointerdown', (e) => {
        if (e.target.closest('button') || e.button > 0) return;
        id = e.pointerId; el.setPointerCapture(id); el.classList.add('is-dragging');
        const r = el.getBoundingClientRect(); ox = e.clientX - r.left; oy = e.clientY - r.top;
        stopAttract();
      });
      el.addEventListener('pointermove', (e) => {
        if (e.pointerId !== id) return;
        const s = sRect();
        const x = Math.min(Math.max(0, e.clientX - s.left - ox), s.width - el.offsetWidth);
        const y = Math.min(Math.max(0, e.clientY - s.top - oy), s.height - el.offsetHeight);
        el.style.left = x + 'px'; el.style.top = y + 'px'; pin.moved = true;
      });
      const end = (e) => { if (e.pointerId !== id) return; id = null; el.classList.remove('is-dragging'); layoutShelf(); };
      el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end);
    }

    /* ---- Actions ---- */
    function act(name) {
      if (!current) return;
      const { text, match } = current;
      switch (name) {
        case 'copy': copy(text); return success(P.copied);
        case 'plain': copy(text); return success(P.copied);
        case 'color': case 'math': copy(match.value); return success(P.copied);
        case 'open': toast(`↗ ${P.opened} · ${match.value}`); return hide();
        case 'search': toast(`⌕ ${P.searched}`); return hide();
        case 'pin': addPin(text); return success(P.pinned);
        case 'aa': return menu.hidden ? openMenu(pill.querySelector('[data-act="aa"]')) : closeMenu();
        default: return undefined;
      }
    }
    // Keep the text selection alive while clicking pill/menu (like a non-activating NSPanel).
    [pill, menu].forEach((el) => {
      el.addEventListener('mousedown', (e) => e.preventDefault());
      el.addEventListener('pointerenter', () => { hovering = true; });
      el.addEventListener('pointerleave', () => { hovering = false; });
    });
    pill.addEventListener('click', (e) => { const b = e.target.closest('[data-act]'); if (b) { stopAttract(); act(b.dataset.act); } });
    menu.addEventListener('click', (e) => {
      const b = e.target.closest('[data-tf]'); if (!b || !current) return;
      copy(Analyzer.transform(current.text, b.dataset.tf)); closeMenu(); success(P.copied);
    });

    /* ---- Selection input: mouse drag, double-click, tap, keyboard ---- */
    function selectToken(tok) {
      const range = document.createRange(); range.selectNodeContents(tok);
      const sel = getSelection(); sel.removeAllRanges(); sel.addRange(range);
      return range;
    }
    function fromSelection(target) {
      const sel = getSelection();
      if (sel && !sel.isCollapsed && sel.rangeCount && doc.contains(sel.anchorNode) && doc.contains(sel.focusNode)) {
        const range = sel.getRangeAt(0);
        const rects = range.getClientRects();
        const rect = rects.length ? rects[0] : range.getBoundingClientRect();
        if (rect.width < 3.5 && rect.height < 3.5) return; // ignore micro-drags (< 3.5 pt)
        show(sel.toString(), rect);
        return;
      }
      const tok = target.closest && target.closest('.tok');
      if (tok) { const r = selectToken(tok); show(tok.textContent, r.getClientRects()[0] || tok.getBoundingClientRect()); }
    }
    doc.addEventListener('pointerup', (e) => { stopAttract(); setTimeout(() => fromSelection(e.target), 10); });
    doc.addEventListener('keydown', (e) => {
      const tok = e.target.closest('.tok');
      if (tok && (e.key === 'Enter' || e.key === ' ')) {
        e.preventDefault(); stopAttract();
        const r = selectToken(tok); show(tok.textContent, r.getClientRects()[0] || tok.getBoundingClientRect());
        pill.querySelector('.seg')?.focus({ preventScroll: true });
      }
    });
    stage.addEventListener('pointerdown', (e) => {
      if (!e.target.closest('#pill, #aaMenu, .pin-card, .tok')) {
        if (!e.target.closest('#doc')) { getSelection()?.removeAllRanges(); hide(); }
      }
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !pill.hidden) { hide(); } });
    addEventListener('resize', () => { hide(); layoutShelf(); }, { passive: true });

    /* ---- Attract mode: demo the four examples until the visitor takes over ---- */
    const toks = $$('.tok', doc);
    function attractStep() {
      if (!attract) return;
      $$('.tok.is-sel', doc).forEach((t) => t.classList.remove('is-sel'));
      const tok = toks[attractIdx % toks.length]; attractIdx++;
      tok.classList.add('is-sel');
      show(tok.textContent, tok.getClientRects()[0] || tok.getBoundingClientRect(), { demo: true });
      if (tok.dataset.kind === 'note' && pins.length === 0) {
        setTimeout(() => { if (attract && current) { addPin(current.text); success(P.pinned); } }, 1400);
      }
      attractTimer = setTimeout(attractStep, 3000);
    }
    function stopAttract() {
      if (!attract) return;
      attract = false; clearTimeout(attractTimer);
      $$('.tok.is-sel', doc).forEach((t) => t.classList.remove('is-sel'));
      hud('', H.statusIdle);
    }
    stage.addEventListener('keydown', stopAttract, { once: true });
    if (attract) {
      const so = new IntersectionObserver(([en]) => {
        if (!attract) { so.disconnect(); return; }
        clearTimeout(attractTimer);
        if (en.isIntersecting) attractTimer = setTimeout(attractStep, 900); else hide();
      }, { threshold: 0.45 });
      so.observe(stage);
    }
  }

  /* ---------------- Lite-YouTube facade ---------------- */
  $$('lite-yt').forEach((el) => {
    const id = (el.dataset.videoid || '').trim();
    const btn = el.querySelector('.lyt__play');
    if (!/^[\w-]{11}$/.test(id)) {
      el.setAttribute('data-pending', '');
      btn.setAttribute('aria-disabled', 'true');
      btn.setAttribute('aria-label', (T.tutorial && T.tutorial.soon) || 'Coming soon');
      return;
    }
    el.querySelector('.lyt__poster').style.backgroundImage = `url(https://i.ytimg.com/vi/${id}/hqdefault.jpg)`;
    el.querySelector('.lyt__pill').remove();
    let warmed = false;
    el.addEventListener('pointerover', () => {
      if (warmed) return; warmed = true;
      const l = document.createElement('link'); l.rel = 'preconnect'; l.href = 'https://www.youtube-nocookie.com'; document.head.appendChild(l);
    }, { once: true });
    btn.addEventListener('click', () => {
      const f = document.createElement('iframe');
      f.src = `https://www.youtube-nocookie.com/embed/${id}?autoplay=1&rel=0&modestbranding=1&playsinline=1`;
      f.title = el.dataset.title || 'TapCopy tutorial';
      f.allow = 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; fullscreen';
      f.allowFullscreen = true;
      el.replaceChildren(f);
      f.focus();
    });
  });

  /* ---------------- Trial form → /api/trial → .dmg (never blocks the download) ---------------- */
  const form = $('#trialForm');
  if (form) form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = form.email.value.trim();
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) { form.email.setCustomValidity(' '); form.email.reportValidity(); return; }
    form.email.setCustomValidity('');
    form.classList.add('is-busy');
    let url = form.dataset.download;
    try {
      const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 3000);
      const res = await fetch(form.action, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ email: email || null, lang: form.lang.value, source: 'landing' }), signal: ctrl.signal,
      });
      clearTimeout(t);
      if (res.ok) { const data = await res.json().catch(() => ({})); if (data && typeof data.downloadUrl === 'string' && data.downloadUrl.startsWith('/')) url = data.downloadUrl; }
    } catch (_) { /* offline or endpoint missing: fall back to direct download */ }
    window.dispatchEvent(new CustomEvent('tapcopy:trial', { detail: { withEmail: !!email } }));
    location.assign(url);
    setTimeout(() => form.classList.remove('is-busy'), 1500);
  });
  $('#trialEmail')?.addEventListener('input', (e) => e.target.setCustomValidity(''));

  /* ---------------- Checkout hooks (backend owns /checkout/:plan) ---------------- */
  $$('[data-checkout]').forEach((a) => a.addEventListener('click', () => {
    window.dispatchEvent(new CustomEvent('tapcopy:checkout', { detail: { plan: a.dataset.checkout, price: a.dataset.price, currency: a.dataset.currency } }));
  }));
})();
