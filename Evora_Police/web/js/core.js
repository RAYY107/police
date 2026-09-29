/* Evora_Police — NUI core. Player-provided data is ALWAYS rendered as text (never innerHTML). */
(function () {
  const E = (window.Evora = window.Evora || {});
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Evora_Police';
  E.resource = resource;
  E.locale = {};
  E.cfg = { ui: {}, confirm: { accept: 'F5', reject: 'F6' } };
  E.state = {};
  E.dev = typeof GetParentResourceName !== 'function';

  /* ---------------------------------------------------------------- DOM */
  function h(tag, props, ...children) {
    const el = document.createElement(tag);
    if (props) {
      for (const key of Object.keys(props)) {
        const v = props[key];
        if (v === null || v === undefined || v === false) continue;
        if (key === 'class') el.className = v;
        else if (key === 'style' && typeof v === 'object') Object.assign(el.style, v);
        else if (key === 'dataset') Object.assign(el.dataset, v);
        else if (key === 'html') el.innerHTML = v; // trusted constants only (icons)
        else if (key.startsWith('on') && typeof v === 'function') el.addEventListener(key.slice(2).toLowerCase(), v);
        else el.setAttribute(key, v === true ? '' : String(v));
      }
    }
    append(el, children);
    return el;
  }
  function append(el, children) {
    for (const c of children.flat(Infinity)) {
      if (c === null || c === undefined || c === false) continue;
      el.appendChild(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return el;
  }
  E.h = h;
  E.append = append;
  E.$ = (sel, root) => (root || document).querySelector(sel);
  E.clear = (el) => { while (el && el.firstChild) el.removeChild(el.firstChild); return el; };
  E.icon = (name, size, stroke) => h('span', { class: 'ico', html: window.EvoraIcons.svg(name, size, stroke) });
  // Every logo instance gets its own gradient id: a shared id breaks every copy
  // once the first one sits inside a display:none layer.
  let logoSeq = 0;
  E.logo = (cls) => h('span', { class: 'logo ' + (cls || ''), html: window.EvoraIcons.LOGO.replace(/evg/g, 'evg' + (++logoSeq)) });

  /* ------------------------------------------------------------- Locale */
  E.t = function (key, vars, fallback) {
    let s = E.locale[key];
    if (s === undefined) s = fallback;
    if (s === undefined) return key;
    if (vars) s = s.replace(/\{(\w+)\}/g, (m, k) => (vars[k] === undefined ? m : String(vars[k])));
    return s;
  };

  /* --------------------------------------------------------- Formatting */
  const AR_DIGITS = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  E.digits = function (s) {
    s = String(s);
    return E.cfg.ui && E.cfg.ui.ArabicDigits ? s.replace(/\d/g, (d) => AR_DIGITS[+d]) : s;
  };
  const pad = (n) => String(Math.floor(n)).padStart(2, '0');
  E.clock = (sec) => { sec = Math.max(0, Math.floor(sec || 0)); return E.digits(pad(sec / 3600) + ':' + pad((sec % 3600) / 60) + ':' + pad(sec % 60)); };
  E.mmss = (sec) => { sec = Math.max(0, Math.floor(sec || 0)); return E.digits(pad(sec / 60) + ':' + pad(sec % 60)); };
  E.hours = function (sec) {
    sec = Math.max(0, Math.floor(sec || 0));
    const hrs = Math.floor(sec / 3600), min = Math.floor((sec % 3600) / 60);
    if (hrs > 0 && min > 0) return E.digits(E.t('fmt_hm', { h: hrs, m: min }, '{h} س {m} د'));
    if (hrs > 0) return E.digits(E.t('fmt_h', { h: hrs }, '{h} س'));
    return E.digits(E.t('fmt_m', { m: min }, '{m} د'));
  };
  E.money = (n) => E.digits(Math.floor(n || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ','));
  E.date = function (ts) {
    if (!ts) return '—';
    const d = new Date(ts * 1000);
    return E.digits(d.getFullYear() + '/' + pad(d.getMonth() + 1) + '/' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()));
  };
  E.ago = function (ts) {
    if (!ts) return '';
    const diff = Math.max(0, Math.floor(Date.now() / 1000 - ts));
    if (diff < 60) return E.t('ago_now', null, 'الآن');
    if (diff < 3600) return E.digits(E.t('ago_m', { n: Math.floor(diff / 60) }, 'منذ {n} د'));
    if (diff < 86400) return E.digits(E.t('ago_h', { n: Math.floor(diff / 3600) }, 'منذ {n} س'));
    return E.digits(E.t('ago_d', { n: Math.floor(diff / 86400) }, 'منذ {n} يوم'));
  };
  E.initials = (name) => (String(name || '?').trim().charAt(0) || '?').toUpperCase();

  E.avatar = function (name, url, size) {
    const box = h('div', { class: 'avatar', style: size ? { width: size + 'px', height: size + 'px', fontSize: Math.round(size * 0.42) + 'px' } : null }, E.initials(name));
    if (url && /^https:\/\//.test(url)) {
      const img = h('img', { alt: '', referrerpolicy: 'no-referrer' });
      img.onload = () => { E.clear(box); box.appendChild(img); box.classList.add('has-img'); };
      img.src = url;
    }
    return box;
  };

  /* ---------------------------------------------------------- NUI bridge */
  E.post = async function (name, data) {
    if (E.dev) return E.devPost ? E.devPost(name, data || {}) : { ok: false, data: 'dev' };
    try {
      const res = await fetch('https://' + resource + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
      });
      return await res.json();
    } catch (e) {
      return { ok: false, data: String(e) };
    }
  };

  // Server action through the client: returns { ok, data }
  E.rpc = async function (name, payload) {
    const r = await E.post('rpc', { name, payload: payload || {} });
    return r || { ok: false, data: 'error' };
  };

  /* ------------------------------------------------------ Message router */
  const handlers = {};
  E.on = function (action, fn) { (handlers[action] = handlers[action] || []).push(fn); };
  E.emit = function (action, data) { (handlers[action] || []).forEach((fn) => { try { fn(data || {}); } catch (err) { console.error('[Evora]', action, err); } }); };
  window.addEventListener('message', (ev) => {
    const msg = ev.data;
    if (!msg || typeof msg.action !== 'string') return;
    E.emit(msg.action, msg.data);
  });

  E.on('init', (d) => {
    E.locale = d.locale || {};
    E.cfg = Object.assign(E.cfg, d);
    if (d.ui && d.ui.Accent) document.documentElement.style.setProperty('--accent', d.ui.Accent);
    E.emit('ready', d);
  });
  E.on('state', (s) => { E.state = s || {}; });

  /* ---------------------------------------------------------- ESC stack */
  const escStack = [];
  E.pushEsc = function (id, fn) { E.popEsc(id); escStack.push({ id, fn }); };
  E.popEsc = function (id) { const i = escStack.findIndex((x) => x.id === id); if (i >= 0) escStack.splice(i, 1); };
  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape' && escStack.length) {
      ev.preventDefault();
      const top = escStack[escStack.length - 1];
      top.fn();
    }
    E.emit('key', ev);
  });

  /* -------------------------------------------------------------- Toasts */
  E.toast = function (message, kind, duration) {
    E.emit('toast', { message, kind: kind || 'info', duration: duration || 5 });
  };

  document.addEventListener('DOMContentLoaded', () => { E.post('ready', {}); });
})();
