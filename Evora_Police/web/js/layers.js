/* Evora_Police — overlay layers (everything except the iPad). */
(function () {
  const E = window.Evora;
  const h = E.h;
  const $ = (id) => document.getElementById(id);
  const show = (el) => { el.classList.remove('hidden'); };
  const hide = (el) => { el.classList.add('hidden'); };

  /* =============================================================== Broadcasts */
  function hexToRgb(hex) {
    const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(String(hex || '').trim());
    return m ? parseInt(m[1], 16) + ',' + parseInt(m[2], 16) + ',' + parseInt(m[3], 16) : '139,92,246';
  }
  const bcQueue = [];
  let bcBusy = false;
  function nextBroadcast() {
    const d = bcQueue.shift();
    if (!d) { bcBusy = false; return; }
    bcBusy = true;
    const style = d.style || {};
    const accent = d.kind === 'citizens' ? style.citizenAccent || '#f59e0b' : d.kind === 'alert' ? '#ef4444' : style.officerAccent || '#8b5cf6';
    const duration = Math.max(3, d.duration || 12);
    const rgb = hexToRgb(accent);
    const card = h('div', { class: 'broadcast anim-' + (style.animation || 'slide'), style: { top: style.top || '26%', width: style.width || '560px' } },
      h('div', { class: 'bc-glow' }),
      h('div', { class: 'bc-head' },
        h('div', { class: 'bc-icon' }, E.icon(d.kind === 'alert' ? 'siren' : 'megaphone', 22)),
        h('div', { class: 'bc-title' }, d.title || ''),
        h('div', { class: 'bc-brand' }, E.logo('xs'), 'Evora')),
      h('div', { class: 'bc-body' }, d.message || ''),
      d.sender ? h('div', { class: 'bc-foot' }, E.icon('shield', 14), d.sender) : null,
      h('div', { class: 'bc-progress' }, h('i', { style: { animationDuration: duration + 's' } })));
    card.style.setProperty('--bc', accent);
    card.style.setProperty('--bc-line', 'rgba(' + rgb + ',.45)');
    card.style.setProperty('--bc-glow', 'rgba(' + rgb + ',.22)');
    $('broadcasts').appendChild(card);
    requestAnimationFrame(() => card.classList.add('in'));
    setTimeout(() => {
      card.classList.remove('in');
      card.classList.add('out');
      setTimeout(() => { card.remove(); nextBroadcast(); }, 450);
    }, duration * 1000);
  }
  E.on('broadcast', (d) => { bcQueue.push(d); if (!bcBusy) nextBroadcast(); });

  /* =================================================================== Toasts */
  const TOAST_ICON = { success: 'check', error: 'alert', warning: 'alert', info: 'info' };
  E.on('toast', (d) => {
    const kind = d.kind || 'info';
    const t = h('div', { class: 'toast kind-' + kind },
      h('div', { class: 'toast-icon' }, E.icon(TOAST_ICON[kind] || 'info', 18)),
      h('div', { class: 'toast-msg' }, d.message || ''));
    $('toasts').appendChild(t);
    requestAnimationFrame(() => t.classList.add('in'));
    setTimeout(() => { t.classList.remove('in'); setTimeout(() => t.remove(), 350); }, Math.max(2, d.duration || 5) * 1000);
    while ($('toasts').children.length > 5) $('toasts').firstChild.remove();
  });

  /* ============================================================ Confirmation */
  let confirmId = null;
  let confirmTimer = null;
  function answer(accepted) {
    if (!confirmId) return;
    const id = confirmId;
    confirmId = null;
    hide($('confirm'));
    E.post('confirmAnswer', { id, accepted });
  }
  E.on('confirm:show', (d) => {
    confirmId = d.id;
    const root = E.clear($('confirm'));
    const total = Math.max(1, d.timeout || 30);
    const ring = h('div', { class: 'cf-ring', style: { '--p': 1 } }, h('span', { class: 'cf-ring-num' }, E.digits(total)));
    root.appendChild(h('div', { class: 'confirm-card' },
      h('div', { class: 'cf-head' },
        h('div', { class: 'cf-icon' }, E.icon(d.icon === 'jail' ? 'jail' : d.icon === 'fine' ? 'fine' : d.icon === 'impound' ? 'impound' : d.icon === 'recall' ? 'recall' : 'shield', 20)),
        h('div', { class: 'cf-title' }, d.title || ''),
        ring),
      d.message ? h('div', { class: 'cf-msg' }, d.message) : null,
      (d.details && d.details.length) ? h('div', { class: 'cf-details' }, d.details.map((r) => h('div', { class: 'cf-row' }, h('span', null, r[0]), h('b', null, r[1])))) : null,
      h('div', { class: 'cf-actions' },
        h('button', { class: 'btn btn-accept', onclick: () => answer(true) }, h('kbd', null, d.accept || 'F5'), E.t('confirm_hint_accept')),
        h('button', { class: 'btn btn-reject', onclick: () => answer(false) }, h('kbd', null, d.reject || 'F6'), E.t('confirm_hint_reject')))));
    show(root);
    clearInterval(confirmTimer);
    const started = Date.now();
    confirmTimer = setInterval(() => {
      const left = Math.max(0, total - (Date.now() - started) / 1000);
      ring.style.setProperty('--p', left / total);
      ring.firstChild.textContent = E.digits(Math.ceil(left));
      if (left <= 0) clearInterval(confirmTimer);
    }, 200);
  });
  E.on('confirm:hide', () => { confirmId = null; clearInterval(confirmTimer); hide($('confirm')); });
  E.on('key', (ev) => {
    if (!confirmId) return;
    if (ev.key === 'F5') { ev.preventDefault(); answer(true); }
    else if (ev.key === 'F6') { ev.preventDefault(); answer(false); }
  });
  window.addEventListener('keydown', (ev) => { if (ev.key === 'F5' || ev.key === 'F6') ev.preventDefault(); }, true);

  /* ==================================================================== Hints */
  E.on('hint', (d) => {
    const root = E.clear($('hint'));
    root.appendChild(h('div', { class: 'hint-pill' }, h('kbd', null, d.key || 'E'), h('span', null, d.text || '')));
    show(root);
  });
  E.on('hint:hide', () => hide($('hint')));

  /* ================================================================= Jail HUD */
  let jail = null;
  let jailTick = null;
  function renderJail() {
    if (!jail) return;
    const root = $('jail-hud');
    const pct = jail.total > 0 ? Math.max(0, Math.min(1, jail.remaining / jail.total)) : 0;
    E.$('.jh-time', root).textContent = E.mmss(jail.remaining);
    E.$('.jh-bar i', root).style.width = (pct * 100).toFixed(1) + '%';
  }
  E.on('jail:show', (d) => {
    jail = { remaining: d.remaining, total: d.total, name: d.name, reason: d.reason };
    const root = E.clear($('jail-hud'));
    root.appendChild(h('div', { class: 'jail-card' },
      h('div', { class: 'jh-top' }, E.icon('jail', 16), h('span', null, d.name || '')),
      h('div', { class: 'jh-label' }, E.t('jail_hud_remaining')),
      h('div', { class: 'jh-time mono' }, E.mmss(d.remaining)),
      h('div', { class: 'jh-bar' }, h('i')),
      d.reason ? h('div', { class: 'jh-reason' }, d.reason) : null));
    show(root);
    renderJail();
    clearInterval(jailTick);
    jailTick = setInterval(() => { if (jail && jail.remaining > 0) { jail.remaining -= 1; renderJail(); } }, 1000);
  });
  E.on('jail:sync', (d) => { if (jail) { jail.remaining = d.remaining; renderJail(); } });
  E.on('jail:escape', (d) => {
    const root = $('jail-hud');
    root.classList.remove('flash');
    void root.offsetWidth;
    root.classList.add('flash');
    if (d.message) E.toast(d.message, 'error', 7);
  });
  E.on('jail:hide', () => { jail = null; clearInterval(jailTick); hide($('jail-hud')); });

  /* ================================================================== ID card */
  let idTimer = null;
  E.on('idcard:show', (d) => {
    const root = E.clear($('idcard-layer'));
    const row = (label, value, cls) => h('div', { class: 'idc-field ' + (cls || '') }, h('span', null, label), h('b', null, value));
    root.appendChild(h('div', { class: 'idcard' },
      h('div', { class: 'idc-pattern' }),
      h('div', { class: 'idc-top' },
        h('div', { class: 'idc-titles' }, h('div', { class: 'idc-country' }, d.country || ''), h('div', { class: 'idc-title' }, d.title || '')),
        E.logo('idc-emblem')),
      h('div', { class: 'idc-body' },
        h('div', { class: 'idc-photo' }, E.avatar(d.name, d.avatar, 96)),
        h('div', { class: 'idc-fields' },
          row(E.t('idcard_name'), d.name || ''),
          row(E.t('idcard_id'), E.digits(d.user_id), 'mono'),
          row(E.t('idcard_job'), d.job || '—'),
          d.rank ? row(E.t('idcard_rank'), d.rank + (d.sector ? ' — ' + d.sector : '')) : null)),
      h('div', { class: 'idc-bottom' },
        h('div', { class: 'idc-code' }, Array.from({ length: 28 }, (_, i) => h('i', { style: { width: ((i * 7 + (d.user_id || 1)) % 3 + 1) + 'px' } }))),
        h('div', { class: 'idc-num mono' }, E.digits(String(1000000000 + (d.user_id || 0) * 7919).slice(0, 10))))));
    show(root);
    requestAnimationFrame(() => root.firstChild.classList.add('in'));
    clearTimeout(idTimer);
    idTimer = setTimeout(() => {
      if (root.firstChild) root.firstChild.classList.remove('in');
      setTimeout(() => hide(root), 500);
    }, Math.max(3, d.duration || 10) * 1000);
  });

  /* =================================================================== Panels */
  const panelRoot = $('panel-layer');
  let panelKind = null;
  function closePanel() {
    hide(panelRoot);
    panelKind = null;
    E.popEsc('panel');
    E.post('close', { layer: 'panel' });
  }
  function sheet(title, icon, body, wide) {
    return h('div', { class: 'sheet-backdrop' },
      h('div', { class: 'sheet' + (wide ? ' wide' : '') },
        h('div', { class: 'sheet-head' },
          h('div', { class: 'sheet-title' }, h('span', { class: 'sheet-icon' }, E.icon(icon, 20)), title),
          h('button', { class: 'icon-btn', onclick: closePanel, title: E.t('close') }, E.icon('x', 18))),
        h('div', { class: 'sheet-body' }, body)));
  }
  const empty = (text) => h('div', { class: 'empty' }, E.icon('info', 28), h('div', null, text || E.t('none')));
  const kv = (label, value, cls) => h('div', { class: 'kv ' + (cls || '') }, h('span', null, label), h('b', null, value));
  const statusBadge = (status) => h('span', { class: 'badge st-' + status }, E.t('status_' + status) !== 'status_' + status ? E.t('status_' + status) : status);

  function personHeader(name, id, avatar, extra) {
    return h('div', { class: 'person' }, E.avatar(name, avatar, 64),
      h('div', { class: 'person-info' }, h('div', { class: 'person-name' }, name || '—'),
        h('div', { class: 'person-meta' }, h('span', { class: 'chip mono' }, 'ID ' + E.digits(id)), extra || null)));
  }

  function fineRow(f, opts) {
    return h('div', { class: 'row-card fine-row' + (f.status === 'paid' ? ' is-paid' : '') },
      opts && opts.check ? h('input', { type: 'checkbox', class: 'chk', checked: true, dataset: { id: f.id } }) : null,
      h('div', { class: 'grow' },
        h('div', { class: 'row-title' }, f.label, h('span', { class: 'muted' }, ' • ' + (f.category || ''))),
        h('div', { class: 'row-sub' }, E.t('fines_officer') + ': ' + (f.officer ? f.officer.name + ' | ID ' + f.officer.id : '—') + ' • ' + E.date(f.createdAt))),
      h('div', { class: 'amount' }, '$' + E.money(f.amount)),
      f.status ? h('span', { class: 'badge ' + (f.status === 'paid' ? 'ok' : 'bad') }, f.status === 'paid' ? E.t('fines_paid') : E.t('fines_unpaid')) : null);
  }

  const renderers = {
    citizen(d) {
      return h('div', { class: 'stack' },
        personHeader(d.name, d.user_id, d.avatar, h('span', { class: 'chip ' + (d.online ? 'ok' : '') }, d.online ? E.t('online') : E.t('offline'))),
        h('div', { class: 'kv-grid' },
          kv(E.t('citizen_job'), d.job || '—'),
          kv(E.t('citizen_wanted'), d.wanted && d.wanted.active ? E.t('citizen_wanted_yes') : E.t('citizen_wanted_no'), d.wanted && d.wanted.active ? 'bad' : 'ok'),
          kv(E.t('citizen_fines'), E.digits(d.fines ? d.fines.count : 0)),
          kv(E.t('citizen_fines_total'), '$' + E.money(d.fines ? d.fines.total : 0))),
        d.jailed ? h('div', { class: 'callout bad' }, E.icon('jail', 16), E.t('citizen_jailed')) : null,
        d.wanted && d.wanted.active ? h('div', { class: 'callout bad' }, E.icon('target', 16), h('div', null, h('b', null, d.wanted.reason), h('div', { class: 'muted' }, (d.wanted.by || '') + ' • ' + E.date(d.wanted.createdAt)))) : null,
        d.fines && d.fines.list && d.fines.list.length ? h('div', { class: 'list' }, d.fines.list.map((f) => fineRow(f))) : null);
    },
    fines(d) {
      return h('div', { class: 'stack' },
        personHeader(d.name, d.user_id, null, h('span', { class: 'chip bad' }, E.t('fines_unpaid') + ': $' + E.money(d.unpaidTotal))),
        d.list && d.list.length ? h('div', { class: 'list' }, d.list.map((f) => fineRow(f))) : empty(E.t('fines_none')));
    },
    jail(d) {
      return h('div', { class: 'stack' },
        personHeader(d.name, d.user_id, null, h('span', { class: 'chip ' + (d.jailed ? 'bad' : 'ok') }, d.jailed ? E.t('jail_is_jailed') : E.t('jail_not_jailed'))),
        d.jailed ? h('div', { class: 'kv-grid' },
          kv(E.t('jail_remaining'), E.mmss(d.remaining), 'mono big'),
          kv(E.t('jail_name'), d.jailName || ''),
          kv(E.t('jail_reason'), d.reason || '—'),
          kv(E.t('jail_officer'), d.officer ? d.officer.name + ' | ID ' + d.officer.id : '—')) : null);
    },
    impound(d) {
      return h('div', { class: 'stack' },
        personHeader(d.name, d.user_id),
        d.list && d.list.length ? h('div', { class: 'list' }, d.list.map((r) => h('div', { class: 'row-card' },
          h('div', { class: 'plate' }, r.plate),
          h('div', { class: 'grow' },
            h('div', { class: 'row-title' }, (r.model || '—') + ' • ' + r.reason),
            h('div', { class: 'row-sub' }, r.location + ' • ' + (r.officer ? r.officer.name + ' | ID ' + r.officer.id : '') + ' • ' + E.date(r.createdAt))),
          h('div', { class: 'amount' }, '$' + E.money(r.fee)),
          h('span', { class: 'badge ' + (r.status === 'impounded' ? 'bad' : 'ok') }, r.status === 'impounded' ? E.t('impound_status_impounded') : E.t('impound_status_released'))))) : empty(E.t('impound_none')));
    },
    search(d) {
      return h('div', { class: 'stack' },
        personHeader(d.name, d.user_id, null, d.money !== null && d.money !== undefined ? h('span', { class: 'chip' }, E.t('search_money') + ': $' + E.money(d.money)) : null),
        h('div', { class: 'section-title' }, E.icon('grid', 16), E.t('search_items')),
        d.items && d.items.length ? h('div', { class: 'item-grid' }, d.items.map((it) => h('div', { class: 'item' + (it.contraband ? ' contraband' : '') },
          h('div', { class: 'item-name' }, it.label), h('div', { class: 'item-amount mono' }, '×' + E.digits(it.amount)),
          it.contraband ? h('span', { class: 'badge bad' }, E.t('search_contraband')) : null))) : empty(E.t('search_empty')),
        d.weapons ? h('div', { class: 'section-title' }, E.icon('target', 16), E.t('search_weapons')) : null,
        d.weapons ? (d.weapons.length ? h('div', { class: 'item-grid' }, d.weapons.map((w) => h('div', { class: 'item' }, h('div', { class: 'item-name mono' }, w.name.replace('WEAPON_', '')), h('div', { class: 'item-amount mono' }, E.digits(w.ammo))))) : empty(E.t('search_empty'))) : null);
    },
    vehicle(d) {
      const body = h('div', { class: 'stack' },
        h('div', { class: 'vehicle-head' }, h('div', { class: 'plate big' }, d.plate), h('div', null, h('div', { class: 'row-title' }, d.model || '—'),
          h('div', { class: 'row-sub' }, E.t('vehicle_owner') + ': ' + (d.owner ? d.owner.name + ' | ID ' + d.owner.id : '—')))),
        d.items && d.items.length ? h('div', { class: 'item-grid' }, d.items.map((it) => h('div', { class: 'item' + (it.contraband ? ' contraband' : '') },
          h('div', { class: 'item-name' }, it.label), h('div', { class: 'item-amount mono' }, '×' + E.digits(it.amount)),
          it.contraband ? h('span', { class: 'badge bad' }, E.t('search_contraband')) : null))) : empty(E.t('search_empty')));
      if (d.canSeize) {
        const btn = h('button', { class: 'btn btn-danger wide', onclick: async () => {
          btn.disabled = true;
          const r = await E.post('panelAction', { action: 'vehicleSeize', token: d.token });
          if (r && r.ok) { E.toast(E.t('vehicle_seize'), 'success'); d.items = r.data.items; d.canSeize = false; openPanel({ kind: 'vehicle', title: currentTitle, data: d }); }
          else { btn.disabled = false; E.toast(r && r.data, 'error'); }
        } }, E.icon('shield', 16), E.t('vehicle_seize'));
        body.appendChild(btn);
      }
      return body;
    },
    finePay(d) {
      const list = d.list || [];
      const body = h('div', { class: 'stack' },
        h('div', { class: 'pay-summary' }, h('div', null, h('div', { class: 'muted' }, E.t('fines_total')), h('div', { class: 'amount big' }, '$' + E.money(d.total))),
          h('span', { class: 'chip' }, E.digits(d.count || 0) + ' ' + E.t('fines_unpaid'))),
        list.length ? h('div', { class: 'list' }, list.map((f) => fineRow(f, { check: true }))) : empty(E.t('fines_none')));
      if (list.length) {
        const pay = async (all) => {
          const ids = Array.from(body.querySelectorAll('.chk')).filter((c) => c.checked).map((c) => Number(c.dataset.id));
          const r = await E.post('panelAction', { action: 'finesPay', ids, all });
          if (r && r.ok) openPanel({ kind: 'finePay', title: currentTitle, data: r.data });
          else E.toast(r && r.data, 'error');
        };
        body.appendChild(h('div', { class: 'actions' },
          h('button', { class: 'btn btn-primary', onclick: () => pay(true) }, E.icon('cash', 16), E.t('fines_pay_all')),
          h('button', { class: 'btn', onclick: () => pay(false) }, E.icon('check', 16), E.t('fines_pay'))));
      }
      return body;
    },
    impoundPay(d) {
      const list = d.list || [];
      return list.length ? h('div', { class: 'list' }, list.map((r) => {
        const btn = h('button', { class: 'btn btn-primary', onclick: async () => {
          btn.disabled = true;
          const res = await E.post('panelAction', { action: 'impoundPay', id: r.id });
          if (res && res.ok) openPanel({ kind: 'impoundPay', title: currentTitle, data: Object.assign({ location: d.location }, res.data) });
          else { btn.disabled = false; E.toast(res && res.data, 'error'); }
        } }, E.icon('cash', 16), E.t('impound_pay') + ' $' + E.money(r.fee));
        return h('div', { class: 'row-card' }, h('div', { class: 'plate' }, r.plate),
          h('div', { class: 'grow' }, h('div', { class: 'row-title' }, (r.model || '—') + ' • ' + r.reason), h('div', { class: 'row-sub' }, r.location + ' • ' + E.date(r.createdAt))), btn);
      })) : empty(E.t('impound_none'));
    },
  };
  const PANEL_ICONS = { citizen: 'userSearch', fines: 'fine', jail: 'jail', impound: 'impound', search: 'search', vehicle: 'car', finePay: 'cash', impoundPay: 'impound' };
  let currentTitle = '';
  function openPanel(d) {
    const render = renderers[d.kind];
    if (!render) return;
    panelKind = d.kind;
    currentTitle = d.title || '';
    E.clear(panelRoot).appendChild(sheet(currentTitle, PANEL_ICONS[d.kind] || 'info', render(d.data || {}), d.kind === 'search' || d.kind === 'vehicle'));
    show(panelRoot);
    E.pushEsc('panel', closePanel);
  }
  E.on('panel:open', openPanel);
  E.on('panel:close', () => { hide(panelRoot); panelKind = null; E.popEsc('panel'); });

  /* ============================================================ Dialog popup */
  const dialogRoot = $('dialog-layer');
  let dialogId = null;
  function closeDialog(submit) {
    if (dialogId === null) return;
    const id = dialogId;
    dialogId = null;
    E.popEsc('dialog');
    if (submit) {
      const values = {};
      dialogRoot.querySelectorAll('[data-key]').forEach((el) => { values[el.dataset.key] = el.value; });
      E.post('dialogSubmit', { id, values });
    } else {
      E.post('dialogCancel', { id });
    }
    hide(dialogRoot);
  }
  E.on('dialog:open', (d) => {
    dialogId = d.id;
    const fields = (d.fields || []).map((f, i) => h('label', { class: 'field' }, h('span', null, f.label),
      f.type === 'textarea'
        ? h('textarea', { dataset: { key: f.key }, maxlength: f.max || 250, rows: 4, placeholder: f.placeholder || '' }, f.default || '')
        : h('input', { dataset: { key: f.key }, type: f.type === 'number' ? 'number' : 'text', maxlength: f.max || 64, placeholder: f.placeholder || '', value: f.default || '', autofocus: i === 0 })));
    const form = h('form', { class: 'stack', onsubmit: (ev) => { ev.preventDefault(); closeDialog(true); } }, fields,
      h('div', { class: 'actions' }, h('button', { class: 'btn btn-primary', type: 'submit' }, E.icon('check', 16), E.t('confirm')),
        h('button', { class: 'btn', type: 'button', onclick: () => closeDialog(false) }, E.t('cancel'))));
    E.clear(dialogRoot).appendChild(h('div', { class: 'sheet-backdrop' }, h('div', { class: 'sheet dialog' },
      h('div', { class: 'sheet-head' }, h('div', { class: 'sheet-title' }, h('span', { class: 'sheet-icon' }, E.icon('edit', 20)), d.title || ''),
        h('button', { class: 'icon-btn', type: 'button', onclick: () => closeDialog(false) }, E.icon('x', 18))),
      h('div', { class: 'sheet-body' }, form))));
    show(dialogRoot);
    E.pushEsc('dialog', () => closeDialog(false));
    const first = dialogRoot.querySelector('input, textarea');
    if (first) setTimeout(() => first.focus(), 30);
  });
  E.on('dialog:close', () => { dialogId = null; E.popEsc('dialog'); hide(dialogRoot); });

  /* ============================================================ Builtin menu */
  const menuRoot = $('menu-layer');
  let menu = null;
  let menuIndex = 0;
  function renderMenu() {
    const items = menu.items || [];
    E.clear(menuRoot).appendChild(h('div', { class: 'menu' },
      h('div', { class: 'menu-head' }, E.logo('sm'), h('div', null, h('div', { class: 'menu-title' }, menu.title || ''), menu.subtitle ? h('div', { class: 'menu-sub' }, menu.subtitle) : null)),
      h('div', { class: 'menu-items' }, items.map((it, i) => h('button', {
        class: 'menu-item' + (i === menuIndex ? ' active' : ''),
        onmouseenter: () => { menuIndex = i; renderMenu(); },
        onclick: () => selectMenu(i),
      }, h('div', { class: 'mi-label' }, it.label), it.description ? h('div', { class: 'mi-desc' }, it.description) : null))),
      h('div', { class: 'menu-foot' }, '↑ ↓ • Enter • ' + (menu.back ? 'Backspace ' + E.t('back') : 'Esc ' + E.t('close')))));
    show(menuRoot);
  }
  function selectMenu(i) {
    if (!menu) return;
    const token = menu.token;
    menu = null;
    hide(menuRoot);
    E.popEsc('menu');
    E.post('menuSelect', { token, index: i + 1 });
  }
  function closeMenu(back) {
    if (!menu) return;
    const token = menu.token;
    menu = null;
    hide(menuRoot);
    E.popEsc('menu');
    E.post(back ? 'menuBack' : 'menuClose', { token });
  }
  E.on('menu:open', (d) => { menu = d; menuIndex = 0; renderMenu(); E.pushEsc('menu', () => closeMenu(false)); });
  E.on('menu:close', () => { menu = null; hide(menuRoot); E.popEsc('menu'); });
  E.on('key', (ev) => {
    if (!menu) return;
    const n = (menu.items || []).length;
    if (ev.key === 'ArrowDown') { menuIndex = (menuIndex + 1) % Math.max(1, n); renderMenu(); }
    else if (ev.key === 'ArrowUp') { menuIndex = (menuIndex - 1 + n) % Math.max(1, n); renderMenu(); }
    else if (ev.key === 'Enter' && n) { ev.preventDefault(); selectMenu(menuIndex); }
    else if (ev.key === 'Backspace') { ev.preventDefault(); closeMenu(menu.back); }
  });

  /* ================================================================= Spectate */
  E.on('spectate:show', (d) => {
    const root = E.clear($('spectate'));
    root.appendChild(h('div', { class: 'spec-top' }, h('span', { class: 'live-dot' }), E.t('spectate_title'), h('b', null, (d.name || '') + ' | ID ' + E.digits(d.id))));
    root.appendChild(h('button', { class: 'spec-stop', onclick: () => E.post('spectateStop', {}) }, h('kbd', null, d.key || 'BACKSPACE'), E.t('spectate_stop')));
    show(root);
  });
  E.on('spectate:hide', () => hide($('spectate')));

  /* ========================================================= Progress & skill */
  let progTimer = null;
  E.on('progress:start', (d) => {
    const root = E.clear($('progress'));
    const bar = h('i');
    const pct = h('span', { class: 'mono' }, '0%');
    root.appendChild(h('div', { class: 'progress-card' }, h('div', { class: 'progress-top' }, h('span', null, d.label || ''), pct), h('div', { class: 'progress-bar' }, bar)));
    show(root);
    const started = Date.now();
    const total = Math.max(1, d.duration || 10) * 1000;
    clearInterval(progTimer);
    progTimer = setInterval(() => {
      const p = Math.min(1, (Date.now() - started) / total);
      bar.style.width = (p * 100).toFixed(1) + '%';
      pct.textContent = E.digits(Math.round(p * 100)) + '%';
      if (p >= 1) clearInterval(progTimer);
    }, 100);
  });
  E.on('progress:stop', () => { clearInterval(progTimer); hide($('progress')); });

  let skill = null;
  E.on('skillcheck:start', (d) => {
    const root = E.clear($('skillcheck'));
    const zone = Math.max(0.06, Math.min(0.5, d.zone || 0.2));
    const start = 0.25 + Math.random() * (0.7 - zone);
    const R = 46, C = 2 * Math.PI * R;
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 120 120');
    const track = document.createElementNS(ns, 'circle');
    Object.entries({ cx: 60, cy: 60, r: R, class: 'sk-track' }).forEach(([k, v]) => track.setAttribute(k, v));
    const arc = document.createElementNS(ns, 'circle');
    Object.entries({ cx: 60, cy: 60, r: R, class: 'sk-zone', 'stroke-dasharray': zone * C + ' ' + C, 'stroke-dashoffset': -start * C, transform: 'rotate(-90 60 60)' }).forEach(([k, v]) => arc.setAttribute(k, v));
    const needle = document.createElementNS(ns, 'line');
    Object.entries({ x1: 60, y1: 60, x2: 60, y2: 12, class: 'sk-needle' }).forEach(([k, v]) => needle.setAttribute(k, v));
    svg.append(track, arc, needle);
    root.appendChild(h('div', { class: 'skill-card' }, svg, h('div', { class: 'sk-key' }, h('kbd', null, d.key || 'E'))));
    show(root);
    skill = { pos: 0, zoneStart: start, zone, speed: 0.55 * (d.speed || 1), last: performance.now(), done: false };
    const step = (now) => {
      if (!skill || skill.done) return;
      skill.pos = (skill.pos + ((now - skill.last) / 1000) * skill.speed) % 1;
      skill.last = now;
      needle.setAttribute('transform', 'rotate(' + skill.pos * 360 + ' 60 60)');
      if (now - skill.startedAt > 6000) return finishSkill(false);
      requestAnimationFrame(step);
    };
    skill.startedAt = performance.now();
    requestAnimationFrame(step);
  });
  function finishSkill(success) {
    if (!skill || skill.done) return;
    skill.done = true;
    $('skillcheck').classList.add(success ? 'ok' : 'bad');
    setTimeout(() => { $('skillcheck').classList.remove('ok', 'bad'); hide($('skillcheck')); }, 350);
    skill = null;
    E.post('skillcheck', { success });
  }
  E.on('key', (ev) => {
    if (!skill || ev.code !== 'KeyE') return;
    const p = skill.pos;
    finishSkill(p >= skill.zoneStart && p <= skill.zoneStart + skill.zone);
  });

  /* ============================================================ Wanted alert */
  let wantedTimer = null;
  E.on('wanted:alert', (d) => {
    const root = E.clear($('wanted-alert'));
    const q = d.quickOpen || E.cfg.wanted || {};
    root.appendChild(h('div', { class: 'wanted-card' },
      h('div', { class: 'wa-head' }, E.icon('target', 18), h('b', null, E.t('wanted_title'))),
      h('div', { class: 'wa-name' }, (d.name || '') + ' | ID ' + E.digits(d.user_id)),
      h('div', { class: 'wa-reason' }, d.reason || ''),
      q.enabled ? h('div', { class: 'wa-quick' }, h('kbd', null, q.label || 'G'), E.t('wanted_quick', { key: q.label || 'G' })) : null,
      h('div', { class: 'wa-bar' }, h('i', { style: { animationDuration: (q.seconds || 10) + 's' } }))));
    show(root);
    clearTimeout(wantedTimer);
    wantedTimer = setTimeout(() => hide(root), (q.seconds || 10) * 1000);
  });
  E.on('wanted:alertHide', () => hide($('wanted-alert')));

  /* ======================================================== Security alert chip */
  E.on('alert:status', (d) => {
    const root = E.clear($('alert-status'));
    if (!d.active) return hide(root);
    root.appendChild(h('div', { class: 'alert-chip' }, E.icon('siren', 16), h('span', null, E.t('alert_zone_chip', { zone: d.label || '' }))));
    show(root);
  });
})();
