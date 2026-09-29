/* Evora_Police — القائمة العسكرية (police iPad). Every action goes through the server (E.rpc). */
(function () {
  const E = window.Evora;
  const h = E.h;
  const root = document.getElementById('ipad-layer');
  const S = { boot: null, tab: 'office', timers: [], open: false, offset: 0, sub: null, recall: null, recallView: null };

  const now = () => Date.now() / 1000 + S.offset;
  const every = (ms, fn) => { const id = setInterval(fn, ms); S.timers.push(id); return id; };
  const clearTimers = () => { S.timers.forEach(clearInterval); S.timers = []; };
  const perm = (p) => !!(S.boot && S.boot.perms && S.boot.perms[p]);
  const empty = (text, icon) => h('div', { class: 'empty' }, E.icon(icon || 'info', 30), h('div', null, text || E.t('none')));
  const loading = () => h('div', { class: 'loading' }, h('span', { class: 'spinner' }), E.t('loading'));
  const confirmHint = () => E.t('confirm_on_screen', { key: (E.cfg.confirm && E.cfg.confirm.accept) || 'F5' });

  const TABS = [
    { id: 'office', icon: 'office', label: 'tab_office' },
    { id: 'online', icon: 'users', label: 'tab_online', perm: 'ipad' },
    { id: 'reports', icon: 'report', label: 'tab_reports', perm: 'reports', feature: 'reports' },
    { id: 'wanted', icon: 'target', label: 'tab_wanted', perm: 'ipad', feature: 'wanted' },
    { id: 'affairs', icon: 'shield', label: 'tab_affairs', perm: 'affairs', feature: 'affairs' },
  ];

  function visibleTabs() {
    if (!S.boot) return [];
    if (S.boot.me.vacation) return TABS.filter((t) => t.id === 'office');
    return TABS.filter((t) => (!t.perm || perm(t.perm)) && (!t.feature || S.boot.features[t.feature]));
  }

  /* ---------------------------------------------------------------- Shell */
  function fit() {
    const scaler = E.$('.ipad-scaler', root);
    if (!scaler) return;
    const s = Math.min((window.innerWidth * 0.95) / 1280, (window.innerHeight * 0.93) / 800, 1.35);
    scaler.style.transform = 'scale(' + s.toFixed(3) + ')';
  }
  window.addEventListener('resize', fit);

  function renderShell() {
    const me = S.boot.me;
    const nav = h('nav', { class: 'nav' }, visibleTabs().map((t) =>
      h('button', { class: 'nav-item' + (t.id === S.tab ? ' active' : ''), dataset: { tab: t.id }, onclick: () => go(t.id) },
        h('span', { class: 'nav-ico' }, E.icon(t.icon, 20)), h('span', { class: 'nav-label' }, E.t(t.label)),
        h('span', { class: 'nav-badge hidden', dataset: { badge: t.id } }))));
    const dutyDot = h('span', { class: 'duty-dot' + (S.boot.office.onDuty ? ' on' : '') });
    const clockEl = h('span', { class: 'sb-time mono' });
    const tickClock = () => { const d = new Date(); clockEl.textContent = E.digits(String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')); };
    tickClock();
    const shell = h('div', { class: 'ipad-backdrop' },
      h('div', { class: 'ipad-scaler' },
        h('div', { class: 'ipad' },
          h('div', { class: 'ipad-cam' }),
          h('div', { class: 'screen' },
            h('div', { class: 'statusbar' }, clockEl, h('span', { class: 'sb-net' }, E.t('status_bar_net')),
              h('span', { class: 'sb-bat' }, h('i'), E.digits('92%'))),
            h('div', { class: 'screen-body' },
              h('aside', { class: 'sidebar' },
                h('div', { class: 'brand' }, E.logo('md'), h('div', null, h('div', { class: 'brand-name' }, 'Evora'), h('div', { class: 'brand-sub' }, 'POLICE OPERATIONS'))),
                nav,
                h('div', { class: 'me-card' }, E.avatar(me.name, me.avatar, 42),
                  h('div', { class: 'me-info' }, h('div', { class: 'me-name' }, me.name, dutyDot), h('div', { class: 'me-rank' }, me.vacation ? E.t('office_vacation') : (me.rank || '—')))),
                h('div', { class: 'made' }, 'Evora_Police • ', h('b', null, 'Made By LR'))),
              h('main', { class: 'main' },
                h('header', { class: 'topbar' },
                  h('div', null, h('div', { class: 'page-title' }), h('div', { class: 'page-sub' })),
                  h('div', { class: 'top-actions' },
                    h('button', { class: 'icon-btn', title: E.t('refresh'), onclick: () => go(S.tab, true) }, E.icon('refresh', 18)),
                    h('button', { class: 'icon-btn close', title: E.t('close'), onclick: close }, E.icon('x', 18)))),
                h('section', { class: 'view' })))))),
      h('div', { class: 'modal-host' }));
    E.clear(root).appendChild(shell);
    clearInterval(S.clockTimer);
    S.clockTimer = setInterval(tickClock, 15000);
    fit();
  }

  function setTitle(title, sub) {
    E.$('.page-title', root).textContent = title;
    E.$('.page-sub', root).textContent = sub || (me() ? (me().sectorLabel || me().ministryLabel || '') : '');
  }
  const me = () => S.boot && S.boot.me;

  async function open(tab) {
    if (!S.open) {
      S.open = true;
      E.clear(root).appendChild(h('div', { class: 'ipad-backdrop' }, h('div', { class: 'ipad-boot' }, E.logo('lg'), h('div', { class: 'boot-bar' }, h('i')))));
      root.classList.remove('hidden');
      requestAnimationFrame(() => root.classList.add('in'));
      E.pushEsc('ipad', close);
    }
    const r = await E.rpc('ipad:bootstrap');
    if (!r.ok) {
      E.toast(r.data || E.t('open_ipad_error'), 'error');
      close();
      return;
    }
    S.boot = r.data;
    S.offset = r.data.now - Date.now() / 1000;
    S.tab = visibleTabs().some((t) => t.id === tab) ? tab : 'office';
    renderShell();
    go(S.tab);
  }

  function close() {
    if (!S.open) return;
    S.open = false;
    clearTimers();
    clearInterval(S.clockTimer);
    closeModal();
    root.classList.remove('in');
    E.popEsc('ipad');
    setTimeout(() => { if (!S.open) { root.classList.add('hidden'); E.clear(root); } }, 250);
    E.post('close', { layer: 'ipad' });
  }

  function go(tab, force) {
    if (!S.boot) return;
    if (!visibleTabs().some((t) => t.id === tab)) tab = 'office';
    if (S.tab === tab && !force && S.sub) S.sub = null;
    S.tab = tab;
    clearTimers();
    S.recallView = null;
    root.querySelectorAll('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    const view = E.clear(E.$('.view', root));
    view.classList.remove('enter');
    void view.offsetWidth;
    view.classList.add('enter');
    ({ office: viewOffice, online: viewOnline, reports: viewReports, wanted: viewWanted, affairs: viewAffairs })[tab](view);
  }

  /* ---------------------------------------------------------------- Modal */
  let modalEl = null;
  function closeModal() {
    if (modalEl) { modalEl.remove(); modalEl = null; E.popEsc('ipad-modal'); }
  }
  function modal(opts) {
    closeModal();
    const host = E.$('.modal-host', root);
    modalEl = h('div', { class: 'modal-backdrop', onclick: (ev) => { if (ev.target === modalEl) closeModal(); } },
      h('div', { class: 'modal' + (opts.wide ? ' wide' : '') },
        h('div', { class: 'modal-head' }, h('div', { class: 'modal-title' }, opts.icon ? E.icon(opts.icon, 18) : null, opts.title),
          h('button', { class: 'icon-btn', onclick: closeModal }, E.icon('x', 16))),
        h('div', { class: 'modal-body' }, opts.body),
        opts.actions ? h('div', { class: 'modal-actions' }, opts.actions) : null));
    host.appendChild(modalEl);
    E.pushEsc('ipad-modal', closeModal);
    const first = modalEl.querySelector('input, textarea');
    if (first) setTimeout(() => first.focus(), 30);
    return modalEl;
  }

  // Runs an action and shows the result. Actions needing F5 wait on the server.
  async function act(button, name, payload, successText) {
    if (button) { button.disabled = true; button.classList.add('busy'); }
    const r = await E.rpc(name, payload);
    if (button) { button.disabled = false; button.classList.remove('busy'); }
    if (r.ok) { if (successText) E.toast(successText, 'success'); }
    else E.toast(r.data || E.t('no_data'), 'error');
    return r;
  }

  /* =============================================================== مكتبي */
  function statCard(icon, label, valueEl, accent) {
    return h('div', { class: 'stat' + (accent ? ' accent' : '') }, h('div', { class: 'stat-ico' }, E.icon(icon, 20)),
      h('div', { class: 'stat-label' }, label), h('div', { class: 'stat-value mono' }, valueEl));
  }

  async function viewOffice(view) {
    setTitle(E.t('tab_office'));
    const b = S.boot;
    let o = b.office;
    const fresh = await E.rpc('ipad:office');
    if (S.tab !== 'office') return;
    if (fresh.ok) { o = fresh.data; S.offset = o.now - Date.now() / 1000; b.office = o; }
    const m = b.me;
    const sessionEl = h('span', null, E.clock(o.session));
    const totalEl = h('span', null, E.hours(o.attendance));
    const base = { at: now(), session: o.session, total: o.attendance };
    if (o.onDuty) every(1000, () => {
      const extra = now() - base.at;
      sessionEl.textContent = E.clock(base.session + extra);
      totalEl.textContent = E.hours(base.total + extra);
    });

    const dutyBtn = h('button', { class: 'btn btn-lg ' + (o.onDuty ? 'btn-danger' : 'btn-primary'), onclick: async () => {
      const r = await act(dutyBtn, 'office:clock', {});
      if (r.ok) { b.office.onDuty = r.data.onDuty; go('office', true); const dot = E.$('.duty-dot', root); if (dot) dot.classList.toggle('on', r.data.onDuty); }
    } }, E.icon('power', 18), o.onDuty ? E.t('office_clock_out') : E.t('office_clock_in'));

    const hero = h('div', { class: 'hero' },
      h('div', { class: 'hero-glow' }),
      E.avatar(m.name, m.avatar, 76),
      h('div', { class: 'hero-info' },
        h('div', { class: 'hero-hello' }, E.t('office_welcome') + '،'),
        h('div', { class: 'hero-name' }, m.name),
        h('div', { class: 'hero-tags' },
          h('span', { class: 'chip mono' }, 'ID ' + E.digits(m.user_id)),
          m.rank ? h('span', { class: 'chip accent' }, E.icon('star', 13), m.rank) : null,
          m.sectorLabel ? h('span', { class: 'chip' }, m.sectorLabel) : null,
          m.ministryLabel ? h('span', { class: 'chip' }, m.ministryLabel) : null)),
      h('div', { class: 'hero-duty' },
        h('div', { class: 'duty-state ' + (o.onDuty ? 'on' : 'off') }, h('i'), o.onDuty ? E.t('on_duty') : E.t('off_duty')),
        b.features.clock && perm('clock') && !m.vacation ? dutyBtn : null));

    const stats = h('div', { class: 'stats' },
      statCard('fine', E.t('office_fines'), E.digits(o.finesIssued), true),
      statCard('clock', E.t('office_session'), sessionEl),
      statCard('hourglass', E.t('office_total'), totalEl),
      statCard('jail', E.t('office_jails'), E.digits(o.jailsIssued)));

    // Military code
    const codeValue = h('span', { class: 'code-value mono' }, o.code || '—');
    const codeCard = h('div', { class: 'card' },
      h('div', { class: 'card-head' }, E.icon('radio', 18), h('span', null, E.t('office_code'))),
      h('div', { class: 'code-row' }, codeValue,
        perm('militaryCode') ? h('button', { class: 'btn btn-ghost', onclick: () => {
          const input = h('input', { type: 'text', maxlength: b.codeMax || 12, value: o.code || '', placeholder: E.t('office_code_placeholder') });
          const save = h('button', { class: 'btn btn-primary', onclick: async () => {
            const r = await act(save, 'office:setCode', { code: input.value }, E.t('code_saved'));
            if (r.ok) { o.code = r.data.code; codeValue.textContent = r.data.code || '—'; closeModal(); }
          } }, E.icon('check', 16), E.t('save'));
          modal({ title: E.t('office_code_edit'), icon: 'radio', body: h('label', { class: 'field' }, h('span', null, E.t('office_code')), input), actions: [save] });
        } }, E.icon('edit', 16), E.t('office_code_edit')) : null));

    // Vacation
    const vac = o.vacation || {};
    const vacBody = vac.active
      ? h('div', { class: 'vac-active' },
          h('div', { class: 'muted' }, E.t('office_vacation_active')), h('div', { class: 'vac-date mono' }, E.date(vac.endsAt)),
          h('button', { class: 'btn btn-danger', onclick: async (ev) => { const r = await act(ev.currentTarget, 'vacation:break', {}); if (r.ok) setTimeout(() => open('office'), 400); } },
            E.icon('power', 16), E.t('office_vacation_break')))
      : h('div', { class: 'vac-idle' },
          h('div', null, h('div', { class: 'muted' }, E.t('office_vacation_balance')), h('div', { class: 'vac-balance mono' }, E.digits(o.vacationBalance), h('small', null, ' ' + E.t('days')))),
          b.features.vacation && perm('vacation') ? h('button', { class: 'btn btn-primary', onclick: () => vacationModal(o) }, E.icon('sun', 16), E.t('office_vacation_request')) : null);
    const vacCard = h('div', { class: 'card' }, h('div', { class: 'card-head' }, E.icon('sun', 18), h('span', null, E.t('office_vacation'))), vacBody);

    // Service activity
    const actRow = (icon, label, value) => h('div', { class: 'activity-row' },
      h('span', { class: 'activity-ico' }, E.icon(icon, 16)), h('span', { class: 'grow muted' }, label), h('b', { class: 'mono' }, value));
    const activityCard = h('div', { class: 'card' },
      h('div', { class: 'card-head' }, E.icon('chart', 18), h('span', null, E.t('office_activity'))),
      h('div', { class: 'activity' },
        actRow('report', E.t('office_reports'), E.digits(o.reportsHandled || 0)),
        actRow('car', E.t('office_impounds'), E.digits(o.impoundsIssued || 0)),
        actRow('clock', E.t('office_last_in'), E.date(o.lastClockIn)),
        actRow('power', E.t('office_last_out'), E.date(o.lastClockOut))));

    E.clear(view).append(hero, stats, h('div', { class: 'grid-2' }, codeCard, vacCard), activityCard);
  }

  function vacationModal(o) {
    let chosen = null;
    const opts = S.boot.vacationOptions || {};
    const chips = h('div', { class: 'chips' }, (opts.durations || []).map((d) => {
      const c = h('button', { class: 'chip-btn', onclick: () => { chosen = d.days; custom.value = ''; chips.querySelectorAll('.chip-btn').forEach((x) => x.classList.remove('active')); c.classList.add('active'); } }, d.label);
      return c;
    }));
    const custom = h('input', { type: 'number', min: 1, max: opts.maxCustom || 30, placeholder: E.t('office_vacation_custom'), oninput: () => { chosen = null; chips.querySelectorAll('.chip-btn').forEach((x) => x.classList.remove('active')); } });
    const send = h('button', { class: 'btn btn-primary', onclick: async () => {
      const days = chosen || Number(custom.value);
      if (!days) return;
      const r = await act(send, 'vacation:request', { days });
      if (r.ok) { closeModal(); setTimeout(() => open('office'), 400); }
    } }, E.icon('check', 16), E.t('office_vacation_request'));
    modal({
      title: E.t('vacation_request_title'), icon: 'sun',
      body: h('div', { class: 'stack' },
        h('div', { class: 'callout' }, E.icon('info', 16), E.t('office_vacation_balance') + ': ' + E.digits(o.vacationBalance) + ' ' + E.t('days')),
        h('div', { class: 'muted' }, E.t('vacation_choose')), chips,
        opts.allowCustom ? h('label', { class: 'field' }, h('span', null, E.t('office_vacation_custom')), custom) : null),
      actions: [send],
    });
  }

  /* ============================================================= المتصلين */
  async function viewOnline(view) {
    setTitle(E.t('tab_online'));
    E.clear(view).appendChild(loading());
    const r = await E.rpc('ipad:online');
    if (S.tab !== 'online') return;
    if (!r.ok) return E.clear(view).appendChild(empty(r.data));
    S.offset = r.data.now - Date.now() / 1000;
    const list = r.data.list || [];
    let filter = '';
    const sectors = Array.from(new Set(list.map((o) => o.sectorLabel)));
    const counter = h('div', { class: 'count-pill' }, E.icon('users', 16), E.t('officers_count', { count: E.digits(list.length) }));
    const tableBody = h('div', { class: 'table-body' });
    const draw = () => {
      E.clear(tableBody);
      const rows = list.filter((o) => !filter || o.sectorLabel === filter);
      if (!rows.length) return tableBody.appendChild(empty(E.t('online_empty'), 'users'));
      rows.forEach((o) => {
        const session = h('span', { class: 'mono' }, E.clock(o.session));
        const base = now() - o.session;
        o._el = session; o._base = base;
        tableBody.appendChild(h('div', { class: 'trow' },
          h('div', { class: 'tcell name' }, E.avatar(o.name, null, 34), h('div', null, h('b', null, o.name), h('div', { class: 'muted small' }, o.rank))),
          h('div', { class: 'tcell mono' }, E.digits(o.user_id)),
          h('div', { class: 'tcell' }, h('span', { class: 'chip' }, o.sectorLabel)),
          h('div', { class: 'tcell' }, o.code ? h('span', { class: 'code-pill mono' }, o.code) : h('span', { class: 'muted' }, '—')),
          h('div', { class: 'tcell' }, h('span', { class: 'live' }, h('i'), session))));
      });
    };
    every(1000, () => list.forEach((o) => { if (o._el) o._el.textContent = E.clock(now() - o._base); }));
    const filters = h('div', { class: 'chips' },
      h('button', { class: 'chip-btn active', onclick: (ev) => { filter = ''; mark(ev.currentTarget); draw(); } }, E.t('all_sectors')),
      sectors.map((s) => h('button', { class: 'chip-btn', onclick: (ev) => { filter = s; mark(ev.currentTarget); draw(); } }, s)));
    const mark = (btn) => { filters.querySelectorAll('.chip-btn').forEach((b) => b.classList.remove('active')); btn.classList.add('active'); };
    E.clear(view).append(
      h('div', { class: 'toolbar' }, counter, filters),
      h('div', { class: 'table' },
        h('div', { class: 'thead' }, ['col_name', 'col_id', 'col_sector', 'col_code', 'col_session'].map((k) => h('div', { class: 'tcell' }, E.t(k)))),
        tableBody));
    draw();
  }

  /* ============================================================== البلاغات */
  const STATUS_ICON = { new: 'bolt', claimed: 'check', processing: 'hourglass', closed: 'lock', cancelled: 'x' };
  async function viewReports(view, status) {
    setTitle(E.t('tab_reports'));
    E.clear(view).appendChild(loading());
    const r = await E.rpc('reports:list', { status: status || null });
    if (S.tab !== 'reports') return;
    if (!r.ok) return E.clear(view).appendChild(empty(r.data));
    const counts = r.data.counts || {};
    const openCount = (counts.new || 0) + (counts.claimed || 0) + (counts.processing || 0);
    const tabs = h('div', { class: 'segmented' },
      [[null, 'status_all', openCount], ['new', 'status_new'], ['claimed', 'status_claimed'], ['processing', 'status_processing'], ['closed', 'status_closed'], ['cancelled', 'status_cancelled']]
        .map(([st, key, n]) => h('button', { class: 'seg' + ((status || null) === st ? ' active' : ''), onclick: () => viewReports(view, st) },
          E.t(key), h('span', { class: 'seg-n mono' }, E.digits(n !== undefined ? n : counts[st] || 0)))));
    const list = h('div', { class: 'report-list' });
    (r.data.list || []).forEach((rep) => list.appendChild(reportCard(rep, r.data.me, view, status)));
    if (!(r.data.list || []).length) list.appendChild(empty(E.t('reports_empty'), 'report'));
    E.clear(view).append(tabs, list);
    setBadge('reports', counts.new || 0);
  }

  function reportCard(rep, meId, view, status) {
    const mine = rep.assigned && rep.assigned.id === meId;
    const actions = [];
    const run = (btn, name, payload) => act(btn, name, payload).then((res) => { if (res.ok) viewReports(view, status); });
    if (rep.status === 'new') {
      const b = h('button', { class: 'btn btn-primary', onclick: () => run(b, 'reports:claim', { id: rep.id }) }, E.icon('check', 16), E.t('report_claim'));
      actions.push(b);
    }
    if ((mine || perm('affairs')) && rep.status === 'claimed') {
      const b = h('button', { class: 'btn', onclick: () => run(b, 'reports:setStatus', { id: rep.id, status: 'processing' }) }, E.icon('hourglass', 16), E.t('report_processing'));
      actions.push(b);
    }
    if ((mine || perm('affairs')) && (rep.status === 'claimed' || rep.status === 'processing')) {
      const c = h('button', { class: 'btn btn-success', onclick: () => run(c, 'reports:setStatus', { id: rep.id, status: 'closed' }) }, E.icon('lock', 16), E.t('report_close'));
      const x = h('button', { class: 'btn btn-ghost', onclick: () => run(x, 'reports:setStatus', { id: rep.id, status: 'cancelled' }) }, E.icon('x', 16), E.t('report_cancel'));
      actions.push(c, x);
    }
    if (rep.hasLocation) {
      const w = h('button', { class: 'btn btn-ghost', onclick: () => act(w, 'reports:waypoint', { id: rep.id }) }, E.icon('pin', 16), E.t('report_waypoint'));
      actions.push(w);
    }
    return h('div', { class: 'report st-' + rep.status },
      h('div', { class: 'report-head' },
        h('span', { class: 'report-id mono' }, '#' + E.digits(rep.id)),
        h('span', { class: 'badge st-' + rep.status }, E.icon(STATUS_ICON[rep.status] || 'info', 12), E.t('status_' + rep.status)),
        h('span', { class: 'muted small' }, E.ago(rep.createdAt))),
      h('div', { class: 'report-people' },
        h('div', { class: 'who' }, h('span', { class: 'muted small' }, E.t('report_reporter')), h('b', null, rep.reporter.name), h('span', { class: 'mono small' }, 'ID ' + E.digits(rep.reporter.id))),
        h('span', { class: 'arrow' }, E.icon('chevronLeft', 18)),
        h('div', { class: 'who danger' }, h('span', { class: 'muted small' }, E.t('report_target')), h('b', null, rep.target.name), h('span', { class: 'mono small' }, 'ID ' + E.digits(rep.target.id)))),
      h('div', { class: 'report-reason' }, rep.reason),
      h('div', { class: 'report-foot' },
        rep.assigned ? h('span', { class: 'muted small' }, E.icon('shield', 13), E.t('report_assigned') + ': ' + rep.assigned.name) : h('span'),
        h('div', { class: 'report-actions' }, actions)));
  }

  function setBadge(tab, n) {
    const el = root.querySelector('[data-badge="' + tab + '"]');
    if (!el) return;
    el.textContent = E.digits(n);
    el.classList.toggle('hidden', !n);
  }

  /* ========================================================= مطلوبين الدولة */
  async function viewWanted(view) {
    setTitle(E.t('tab_wanted'));
    E.clear(view).appendChild(loading());
    const r = await E.rpc('wanted:list');
    if (S.tab !== 'wanted') return;
    if (!r.ok) return E.clear(view).appendChild(empty(r.data));
    const list = r.data || [];
    if (!list.length) {
      E.clear(view).appendChild(h('div', { class: 'wanted-empty' }, h('div', { class: 'we-ring' }, E.icon('shield', 44)), h('div', { class: 'we-text' }, E.t('wanted_none'))));
      return;
    }
    const grid = h('div', { class: 'wanted-grid' }, list.map((w) => {
      const remove = perm('wantedClear') ? h('button', { class: 'btn btn-ghost small', onclick: async () => { const res = await act(remove, 'wanted:clear', { id: w.id }); if (res.ok) viewWanted(view); } }, E.icon('trash', 14), E.t('wanted_remove')) : null;
      return h('div', { class: 'poster' },
        h('div', { class: 'poster-band' }, E.icon('target', 14), E.t('wanted_title')),
        h('div', { class: 'poster-top' }, E.avatar(w.target.name, null, 56),
          h('div', null, h('div', { class: 'poster-name' }, w.target.name), h('div', { class: 'poster-id mono' }, 'ID ' + E.digits(w.target.id)),
            h('span', { class: 'chip ' + (w.target.online ? 'ok' : '') }, w.target.online ? E.t('online') : E.t('offline')))),
        h('div', { class: 'poster-rows' },
          h('div', { class: 'kv' }, h('span', null, E.t('wanted_job')), h('b', null, w.job)),
          h('div', { class: 'kv' }, h('span', null, E.t('wanted_by')), h('b', null, w.createdBy.name + ' | ID ' + E.digits(w.createdBy.id))),
          h('div', { class: 'kv' }, h('span', null, E.t('wanted_date')), h('b', { class: 'mono' }, E.date(w.createdAt)))),
        h('div', { class: 'poster-reason' }, h('span', { class: 'muted small' }, E.t('wanted_reason')), h('div', null, w.reason)),
        remove);
    }));
    E.clear(view).append(h('div', { class: 'toolbar' }, h('div', { class: 'count-pill danger' }, E.icon('target', 16), E.t('wanted_count', { count: E.digits(list.length) }))), grid);
  }

  /* ================================================================ الشؤون */
  const TILE_ICON = {
    recruit: 'recruit', broadcastOfficers: 'megaphone', broadcastCitizens: 'megaphone', recall: 'recall', monitor: 'eye',
    vacationBalance: 'sun', officerInquiry: 'userSearch', resetAttendance: 'clock', resetFines: 'fine', resetData: 'reset', statistics: 'trophy',
  };

  async function viewAffairs(view) {
    setTitle(E.t('tab_affairs'));
    E.clear(view).appendChild(loading());
    const r = await E.rpc('affairs:overview');
    if (S.tab !== 'affairs') return;
    if (!r.ok) return E.clear(view).appendChild(empty(r.data));
    S.affairs = r.data;
    const st = r.data.stats;
    const strip = h('div', { class: 'kpis' },
      [['users', 'affairs_officers', st.officers], ['radio', 'affairs_online', st.online], ['power', 'affairs_on_duty', st.onDuty],
        ['report', 'affairs_reports', st.reports], ['target', 'affairs_wanted', st.wanted], ['jail', 'affairs_prisoners', st.prisoners]]
        .map(([icon, key, v]) => h('div', { class: 'kpi' }, E.icon(icon, 18), h('div', { class: 'kpi-v mono' }, E.digits(v)), h('div', { class: 'kpi-l' }, E.t(key)))));
    const scope = h('div', { class: 'scope' }, h('span', { class: 'muted' }, E.icon('shield', 14), E.t('affairs_scope') + ':'),
      (r.data.scope || []).map((s) => h('span', { class: 'chip accent' }, s)));
    const tiles = h('div', { class: 'tiles' }, (r.data.tiles || []).map((id) =>
      h('button', { class: 'tile', onclick: () => openAffair(view, id) },
        h('div', { class: 'tile-ico' }, E.icon(TILE_ICON[id] || 'grid', 24)),
        h('div', { class: 'tile-label' }, E.t('tile_' + id)),
        h('span', { class: 'tile-go' }, E.icon('chevronLeft', 16)))));
    E.clear(view).append(strip, scope, tiles);
  }

  function subView(view, title, icon, body) {
    setTitle(E.t('tab_affairs'), title);
    E.clear(view).append(
      h('div', { class: 'sub-head' },
        h('button', { class: 'btn btn-ghost', onclick: () => viewAffairs(view) }, E.icon('chevronRight', 16), E.t('back')),
        h('div', { class: 'sub-title' }, E.icon(icon, 20), title)),
      body);
  }

  // Scoped officer list with search. onSelect(officer)
  function officerPicker(permName, onSelect, opts) {
    opts = opts || {};
    const list = h('div', { class: 'picker-list' }, loading());
    let selected = null;
    const load = async (query) => {
      const r = await E.rpc('affairs:officers', { perm: permName, query: query || '', onlineOnly: opts.onlineOnly === true });
      E.clear(list);
      if (!r.ok) return list.appendChild(empty(r.data));
      if (!r.data.length) return list.appendChild(empty(E.t('no_officers'), 'users'));
      r.data.forEach((o) => {
        const row = h('button', { class: 'picker-row', onclick: () => {
          list.querySelectorAll('.picker-row').forEach((x) => x.classList.remove('active'));
          row.classList.add('active');
          selected = o;
          onSelect(o);
        } },
          E.avatar(o.name, null, 36),
          h('div', { class: 'grow' }, h('b', null, o.name), h('div', { class: 'muted small' }, (o.rank || '') + (o.sectorLabel ? ' • ' + o.sectorLabel : ''))),
          h('span', { class: 'mono small' }, 'ID ' + E.digits(o.user_id)),
          o.vacation ? h('span', { class: 'badge warn' }, E.t('office_vacation')) : null,
          h('span', { class: 'status-dot ' + (o.onDuty ? 'duty' : o.online ? 'on' : 'off') }));
        list.appendChild(row);
      });
    };
    let t = null;
    const search = h('input', { class: 'search', type: 'text', placeholder: E.t('search'), oninput: () => { clearTimeout(t); t = setTimeout(() => load(search.value), 300); } });
    load('');
    return { el: h('div', { class: 'picker' }, h('div', { class: 'search-box' }, E.icon('search', 16), search), list), get: () => selected, reload: () => load(search.value) };
  }

  function openAffair(view, id) {
    const title = E.t('tile_' + id);
    const icon = TILE_ICON[id] || 'grid';
    const handlers = {
      recruit: () => affRecruit(view, title, icon),
      broadcastOfficers: () => affBroadcast(view, title, icon, 'officers'),
      broadcastCitizens: () => affBroadcast(view, title, icon, 'citizens'),
      recall: () => affRecall(view, title, icon),
      monitor: () => affMonitor(view, title, icon),
      vacationBalance: () => affVacation(view, title, icon),
      officerInquiry: () => affInquiry(view, title, icon),
      resetAttendance: () => affReset(view, title, icon, 'attendance', 'resetAttendance'),
      resetFines: () => affReset(view, title, icon, 'fines', 'resetFines'),
      resetData: () => affReset(view, title, icon, 'data', 'resetData'),
      statistics: () => affTop(view, title, icon),
    };
    if (handlers[id]) handlers[id]();
  }

  function affRecruit(view, title, icon) {
    const pane = h('div', { class: 'pane' });
    const tabs = h('div', { class: 'segmented' });
    const showRecruit = () => {
      E.clear(pane);
      let player = null;
      let rank = null;
      const players = h('div', { class: 'picker-list' });
      const ranksBox = h('div', { class: 'rank-groups' }, empty(E.t('recruit_pick_player'), 'userPlus'));
      const submit = h('button', { class: 'btn btn-primary btn-lg', disabled: true, onclick: async () => {
        const r = await act(submit, 'affairs:recruit', { user_id: player.user_id, rank: rank.group }, E.t('recruit_done'));
        if (r.ok) showRecruit();
      } }, E.icon('userPlus', 18), E.t('recruit'));
      const refresh = () => { submit.disabled = !(player && rank); };
      const loadRanks = async () => {
        const r = await E.rpc('affairs:ranks');
        E.clear(ranksBox);
        if (!r.ok || !r.data.length) return ranksBox.appendChild(empty(r.ok ? E.t('no_data') : r.data));
        r.data.forEach((g) => ranksBox.appendChild(h('div', { class: 'rank-group' }, h('div', { class: 'rank-group-title' }, g.label),
          h('div', { class: 'chips' }, g.ranks.map((rk) => {
            const c = h('button', { class: 'chip-btn', onclick: () => { ranksBox.querySelectorAll('.chip-btn').forEach((x) => x.classList.remove('active')); c.classList.add('active'); rank = rk; refresh(); } }, rk.label);
            return c;
          })))));
      };
      const loadPlayers = async (q) => {
        const r = await E.rpc('affairs:players', { query: q || '' });
        E.clear(players);
        if (!r.ok) return players.appendChild(empty(r.data));
        r.data.forEach((p) => {
          const row = h('button', { class: 'picker-row', onclick: () => { players.querySelectorAll('.picker-row').forEach((x) => x.classList.remove('active')); row.classList.add('active'); player = p; refresh(); if (!ranksBox.dataset.loaded) { ranksBox.dataset.loaded = '1'; loadRanks(); } } },
            E.avatar(p.name, null, 34), h('div', { class: 'grow' }, h('b', null, p.name), h('div', { class: 'muted small' }, p.rank ? p.rank + (p.sectorLabel ? ' • ' + p.sectorLabel : '') : '—')),
            h('span', { class: 'mono small' }, 'ID ' + E.digits(p.user_id)));
          players.appendChild(row);
        });
      };
      let t = null;
      const search = h('input', { class: 'search', type: 'text', placeholder: E.t('recruit_search'), oninput: () => { clearTimeout(t); t = setTimeout(() => loadPlayers(search.value), 300); } });
      loadPlayers('');
      pane.appendChild(h('div', { class: 'split' },
        h('div', { class: 'card' }, h('div', { class: 'card-head' }, E.icon('users', 18), E.t('recruit_pick_player')), h('div', { class: 'search-box' }, E.icon('search', 16), search), players),
        h('div', { class: 'card sticky' }, h('div', { class: 'card-head' }, E.icon('star', 18), E.t('recruit_pick_rank')), ranksBox, h('div', { class: 'card-foot' }, submit))));
    };
    const showDismiss = () => {
      E.clear(pane);
      const info = h('div', { class: 'detail-box' }, empty(E.t('select_officer'), 'userMinus'));
      const picker = officerPicker('dismiss', (o) => {
        const btn = h('button', { class: 'btn btn-danger btn-lg', onclick: async () => {
          E.toast(confirmHint(), 'info', 4);
          const r = await act(btn, 'affairs:dismiss', { user_id: o.user_id }, E.t('dismiss_done'));
          if (r.ok) { picker.reload(); E.clear(info).appendChild(empty(E.t('select_officer'), 'userMinus')); }
        } }, E.icon('userMinus', 18), E.t('dismiss'));
        E.clear(info).append(officerSummary(o), btn);
      });
      pane.appendChild(h('div', { class: 'split' }, h('div', { class: 'card' }, picker.el), h('div', { class: 'card' }, info)));
    };
    const segs = [];
    if (perm('recruit')) segs.push(['recruit', showRecruit]);
    if (perm('dismiss')) segs.push(['dismiss', showDismiss]);
    segs.forEach(([key, fn], i) => tabs.appendChild(h('button', { class: 'seg' + (i === 0 ? ' active' : ''), onclick: (ev) => { tabs.querySelectorAll('.seg').forEach((x) => x.classList.remove('active')); ev.currentTarget.classList.add('active'); fn(); } }, E.t(key))));
    subView(view, title, icon, h('div', { class: 'stack' }, tabs, pane));
    if (segs[0]) segs[0][1]();
  }

  function officerSummary(o) {
    return h('div', { class: 'officer-summary' }, E.avatar(o.name, o.avatar, 60),
      h('div', null, h('div', { class: 'hero-name small' }, o.name),
        h('div', { class: 'hero-tags' }, h('span', { class: 'chip mono' }, 'ID ' + E.digits(o.user_id)),
          o.rank ? h('span', { class: 'chip accent' }, o.rank) : null, o.sectorLabel ? h('span', { class: 'chip' }, o.sectorLabel) : null,
          h('span', { class: 'chip ' + (o.online ? 'ok' : '') }, o.online ? E.t('online') : E.t('offline')))));
  }

  function affBroadcast(view, title, icon, audience) {
    const max = (S.affairs && S.affairs.broadcastMax) || 300;
    const counter = h('span', { class: 'mono muted small' }, E.digits('0/' + max));
    const text = h('textarea', { rows: 6, maxlength: max, placeholder: E.t('broadcast_placeholder'), oninput: () => { counter.textContent = E.digits(text.value.length + '/' + max); } });
    const send = h('button', { class: 'btn btn-primary btn-lg', onclick: async () => {
      if (!text.value.trim()) return;
      const r = await act(send, 'affairs:broadcast', { audience, message: text.value }, E.t('broadcast_sent'));
      if (r.ok) { text.value = ''; counter.textContent = E.digits('0/' + max); }
    } }, E.icon('send', 18), E.t('send'));
    subView(view, title, icon, h('div', { class: 'card broadcast-compose' + (audience === 'citizens' ? ' citizens' : '') },
      h('div', { class: 'compose-preview' }, E.icon('megaphone', 22), h('b', null, audience === 'officers' ? E.t('tile_broadcastOfficers') : E.t('tile_broadcastCitizens'))),
      text, h('div', { class: 'card-foot' }, counter, send)));
  }

  function renderRecall(box, snap) {
    E.clear(box);
    const c = snap.counts || {};
    box.appendChild(h('div', { class: 'kpis small' },
      [['recall_pending', c.pending, ''], ['recall_accepted', c.accepted, 'ok'], ['recall_rejected', c.rejected, 'bad'], ['recall_timeout', c.timeout, 'warn']]
        .map(([k, v, cls]) => h('div', { class: 'kpi ' + cls }, h('div', { class: 'kpi-v mono' }, E.digits(v || 0)), h('div', { class: 'kpi-l' }, E.t(k))))));
    box.appendChild(h('div', { class: 'picker-list' }, (snap.results || []).map((r) => h('div', { class: 'picker-row static' },
      E.avatar(r.name, null, 32), h('div', { class: 'grow' }, h('b', null, r.name), h('div', { class: 'muted small' }, r.rank || '')),
      h('span', { class: 'mono small' }, 'ID ' + E.digits(r.user_id)),
      h('span', { class: 'badge ' + ({ accepted: 'ok', rejected: 'bad', timeout: 'warn' }[r.status] || '') }, E.t('recall_' + r.status))))));
  }

  function affRecall(view, title, icon) {
    const msg = h('input', { type: 'text', maxlength: 200, placeholder: E.t('recall_message') });
    const results = h('div', { class: 'stack' });
    const start = h('button', { class: 'btn btn-primary btn-lg', onclick: async () => {
      const r = await act(start, 'affairs:recall', { message: msg.value });
      if (r.ok) { S.recallView = results; renderRecall(results, r.data); }
    } }, E.icon('recall', 18), E.t('recall_start'));
    subView(view, title, icon, h('div', { class: 'stack' },
      h('div', { class: 'card' }, h('label', { class: 'field' }, h('span', null, E.t('recall_message')), msg), h('div', { class: 'card-foot' }, start)),
      h('div', { class: 'card' }, h('div', { class: 'card-head' }, E.icon('users', 18), E.t('recall_results')), results)));
  }

  function affMonitor(view, title, icon) {
    const picker = officerPicker('monitor', async (o) => {
      const r = await E.rpc('affairs:monitor', { user_id: o.user_id });
      if (r.ok) close(); else E.toast(r.data, 'error');
    }, { onlineOnly: true });
    subView(view, title, icon, h('div', { class: 'stack' }, h('div', { class: 'callout' }, E.icon('eye', 16), E.t('monitor_hint')), h('div', { class: 'card' }, picker.el)));
  }

  function affVacation(view, title, icon) {
    const info = h('div', { class: 'detail-box' }, empty(E.t('select_officer'), 'sun'));
    const picker = officerPicker('vacationBalance', (o) => {
      const days = h('input', { type: 'number', min: 1, max: (S.affairs && S.affairs.vacationMax) || 60, value: 1 });
      const btn = h('button', { class: 'btn btn-primary btn-lg', onclick: async () => {
        const r = await act(btn, 'affairs:vacationBalance', { user_id: o.user_id, days: Number(days.value) }, E.t('vacation_added'));
        if (r.ok) E.toast(E.t('office_vacation_balance') + ': ' + E.digits(r.data.balance), 'info');
      } }, E.icon('plus', 18), E.t('tile_vacationBalance'));
      E.clear(info).append(officerSummary(o), h('label', { class: 'field' }, h('span', null, E.t('vacation_days')), days), btn);
    });
    subView(view, title, icon, h('div', { class: 'split' }, h('div', { class: 'card' }, picker.el), h('div', { class: 'card' }, info)));
  }

  async function officerDetails(box, userId) {
    E.clear(box).appendChild(loading());
    const r = await E.rpc('affairs:officer', { user_id: userId });
    E.clear(box);
    if (!r.ok) return box.appendChild(empty(r.data));
    const d = r.data;
    const kv = (label, value) => h('div', { class: 'kv' }, h('span', null, label), h('b', { class: 'mono' }, value));
    const actions = [];
    const push = (ok, label, iconName, cls, fn) => { if (ok) { const b = h('button', { class: 'btn ' + (cls || ''), onclick: () => fn(b) }, E.icon(iconName, 16), label); actions.push(b); } };
    push(d.actions.monitor, E.t('tile_monitor'), 'eye', '', async () => { const res = await E.rpc('affairs:monitor', { user_id: d.user_id }); if (res.ok) close(); else E.toast(res.data, 'error'); });
    push(d.actions.resetAttendance, E.t('tile_resetAttendance'), 'clock', '', async (b) => { const res = await act(b, 'affairs:reset', { user_id: d.user_id, kind: 'attendance' }, E.t('reset_done')); if (res.ok) officerDetails(box, userId); });
    push(d.actions.resetFines, E.t('tile_resetFines'), 'fine', '', async (b) => { const res = await act(b, 'affairs:reset', { user_id: d.user_id, kind: 'fines' }, E.t('reset_done')); if (res.ok) officerDetails(box, userId); });
    push(d.actions.resetData, E.t('tile_resetData'), 'reset', '', async (b) => { const res = await act(b, 'affairs:reset', { user_id: d.user_id, kind: 'data' }, E.t('reset_done')); if (res.ok) officerDetails(box, userId); });
    push(d.actions.vacationBreak, E.t('office_vacation_break'), 'sun', '', async (b) => { const res = await act(b, 'affairs:vacationBreak', { user_id: d.user_id }, E.t('action_done')); if (res.ok) officerDetails(box, userId); });
    push(d.actions.dismiss, E.t('dismiss'), 'userMinus', 'btn-danger', async (b) => { E.toast(confirmHint(), 'info', 4); const res = await act(b, 'affairs:dismiss', { user_id: d.user_id }, E.t('dismiss_done')); if (res.ok) officerDetails(box, userId); });
    box.append(
      officerSummary(d),
      h('div', { class: 'kv-grid' },
        kv(E.t('officer_attendance'), E.hours(d.attendance)),
        kv(E.t('officer_session'), E.clock(d.session)),
        kv(E.t('officer_fines'), E.digits(d.fines)),
        kv(E.t('officer_jails'), E.digits(d.jails)),
        kv(E.t('officer_reports'), E.digits(d.reports)),
        kv(E.t('officer_impounds'), E.digits(d.impounds)),
        kv(E.t('officer_vacation_balance'), E.digits(d.vacationBalance) + ' ' + E.t('days')),
        kv(E.t('officer_vacation_status'), d.vacation.active ? E.t('officer_vacation_active') + ' ' + E.date(d.vacation.endsAt) : E.t('officer_vacation_none')),
        kv(E.t('office_code'), d.code || '—'),
        kv(E.t('officer_ministry'), d.ministryLabel || '—'),
        kv(E.t('officer_last_in'), E.date(d.lastClockIn)),
        kv(E.t('officer_last_out'), E.date(d.lastClockOut))),
      actions.length ? h('div', { class: 'actions wrap' }, actions) : null);
  }

  function affInquiry(view, title, icon) {
    const box = h('div', { class: 'detail-box' }, empty(E.t('select_officer'), 'userSearch'));
    const picker = officerPicker('officerInquiry', (o) => officerDetails(box, o.user_id));
    subView(view, title, icon, h('div', { class: 'split wide-right' }, h('div', { class: 'card' }, picker.el), h('div', { class: 'card' }, box)));
  }

  function affReset(view, title, icon, kind, permName) {
    const info = h('div', { class: 'detail-box' }, empty(E.t('select_officer'), 'reset'));
    const includes = kind === 'data' && S.affairs ? Object.entries(S.affairs.resetData || {}).filter(([, v]) => v).map(([k]) => E.t('reset_item_' + k)) : null;
    const picker = officerPicker(permName, (o) => {
      const btn = h('button', { class: 'btn btn-danger btn-lg', onclick: async () => {
        E.toast(confirmHint(), 'info', 4);
        await act(btn, 'affairs:reset', { user_id: o.user_id, kind }, E.t('reset_done'));
      } }, E.icon('reset', 18), title);
      E.clear(info).append(officerSummary(o),
        includes ? h('div', { class: 'callout' }, E.icon('info', 16), h('div', null, h('b', null, E.t('reset_data_includes')), ' ' + includes.join('، '))) : null, btn);
    });
    subView(view, title, icon, h('div', { class: 'split' }, h('div', { class: 'card' }, picker.el), h('div', { class: 'card' }, info)));
  }

  async function affTop(view, title, icon) {
    const box = h('div', { class: 'stack' }, loading());
    const send = h('button', { class: 'btn btn-primary', onclick: () => act(send, 'affairs:topWebhook', {}, E.t('top_sent')) }, E.icon('send', 16), E.t('top_send'));
    subView(view, title, icon, h('div', { class: 'card' }, h('div', { class: 'card-head between' }, h('span', null, E.icon('trophy', 18), E.t('top_title')), send), box));
    const r = await E.rpc('affairs:top');
    E.clear(box);
    if (!r.ok) return box.appendChild(empty(r.data));
    if (!r.data.length) return box.appendChild(empty(E.t('no_data'), 'trophy'));
    box.appendChild(h('div', { class: 'table top' },
      h('div', { class: 'thead' }, ['col_rank_pos', 'col_name', 'col_id', 'col_sector', 'col_attendance', 'col_fines', 'col_score'].map((k) => h('div', { class: 'tcell' }, E.t(k)))),
      h('div', { class: 'table-body' }, r.data.map((o) => h('div', { class: 'trow' + (o.position <= 3 ? ' podium p' + o.position : '') },
        h('div', { class: 'tcell' }, h('span', { class: 'medal mono' }, E.digits(o.position))),
        h('div', { class: 'tcell name' }, E.avatar(o.name, null, 30), h('div', null, h('b', null, o.name), h('div', { class: 'muted small' }, o.rank))),
        h('div', { class: 'tcell mono' }, E.digits(o.user_id)),
        h('div', { class: 'tcell' }, h('span', { class: 'chip' }, o.sectorLabel || '—')),
        h('div', { class: 'tcell mono' }, E.hours(o.attendance)),
        h('div', { class: 'tcell mono' }, E.digits(o.fines)),
        h('div', { class: 'tcell mono accent-text' }, E.digits(o.score)))))));
  }

  /* ------------------------------------------------------------- Events */
  E.on('ipad:open', (d) => open(d.tab));
  E.on('ipad:tab', (d) => { if (S.open) go(d.tab); });
  E.on('ipad:close', () => close());
  E.on('ipad:push', (d) => {
    if (!S.open) return;
    if (d.type === 'recall' && S.recallView) renderRecall(S.recallView, d.data);
    if (d.type === 'reports') {
      if (S.tab === 'reports') viewReports(E.$('.view', root));
      else { const el = root.querySelector('[data-badge="reports"]'); if (el) { el.classList.remove('hidden'); el.textContent = '•'; } }
    }
  });
})();
