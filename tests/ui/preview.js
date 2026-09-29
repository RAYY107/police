// Renders the real NUI in headless Chromium with mocked server data, screenshots every screen
// and fails on any console / page error.   Usage:  node tests/ui/preview.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../../Evora_Police/web/index.html');
const OUT = path.resolve(__dirname, 'shots');
const INIT = JSON.parse(fs.readFileSync(path.resolve(__dirname, 'init.json'), 'utf8'));
const EXE = process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

function mockScript() {
  const now = Math.floor(Date.now() / 1000);
  const names = ['Rayy', 'Hossam', 'Nawaf', 'Saad', 'Faisal', 'Turki', 'Majed', 'Abdullah', 'Khalid', 'Omar'];
  const office = { finesIssued: 37, jailsIssued: 12, reportsHandled: 9, impoundsIssued: 4, session: 5025, attendance: 185400, onDuty: true, code: 'A-12', vacationBalance: 7, vacation: { active: false }, lastClockIn: now - 5025, lastClockOut: now - 86400, now };
  const allPerms = ['ipad', 'clock', 'vacation', 'militaryCode', 'reports', 'wanted', 'wantedClear', 'affairs', 'recruit', 'dismiss', 'broadcastOfficers', 'broadcastCitizens', 'recall', 'monitor', 'vacationBalance', 'officerInquiry', 'resetAttendance', 'resetFines', 'resetData', 'statistics'];
  const perms = {}; allPerms.forEach((p) => (perms[p] = true));
  const officers = names.slice(1, 8).map((n, i) => ({ user_id: 17 + i * 3, name: n, rank: ['ضابط أمن عام', 'دورية أمن عام', 'رجل مرور', 'نائب قائد الأمن العام'][i % 4], sectorLabel: i % 3 === 2 ? 'المرور' : 'الأمن العام', ministryLabel: 'وزارة الداخلية', online: i % 4 !== 3, onDuty: i % 2 === 0, vacation: i === 5, order: i }));
  const data = {
    'ipad:bootstrap': { me: { user_id: 42, name: 'Rayy', avatar: null, rank: 'قائد الأمن العام', sectorLabel: 'الأمن العام', ministryLabel: 'وزارة الداخلية', military: true, vacation: false }, perms, features: { clock: true, reports: true, wanted: true, affairs: true, vacation: true }, office, vacationOptions: { durations: [{ days: 1, label: 'يوم واحد' }, { days: 3, label: '3 أيام' }, { days: 7, label: 'أسبوع' }, { days: 14, label: 'أسبوعين' }], allowCustom: true, maxCustom: 30 }, codeMax: 12, now },
    'ipad:office': office,
    'ipad:online': { now, list: officers.filter((o) => o.onDuty).concat([{ user_id: 42, name: 'Rayy', rank: 'قائد الأمن العام', sectorLabel: 'الأمن العام', code: 'A-12', session: 5025 }]).map((o, i) => ({ user_id: o.user_id, name: o.name, rank: o.rank, sectorLabel: o.sectorLabel, code: o.code || ['P-07', 'T-21', 'P-15', 'P-03'][i % 4], session: o.session || 600 + i * 1333 })) },
    'reports:list': { me: 42, counts: { new: 2, claimed: 1, processing: 1, closed: 14, cancelled: 2 }, list: [
      { id: 128, reporter: { id: 55, name: 'Fahad' }, target: { id: 17, name: 'Hossam' }, reason: 'قام بسرقة سيارتي من أمام البنك المركزي وهرب باتجاه الشمال', status: 'new', createdAt: now - 180, hasLocation: true },
      { id: 127, reporter: { id: 61, name: 'Ali' }, target: { id: 33, name: 'Turki' }, reason: 'إطلاق نار عشوائي في ساحة المدينة', status: 'new', createdAt: now - 900, hasLocation: true },
      { id: 125, reporter: { id: 12, name: 'Sultan' }, target: { id: 29, name: 'Majed' }, reason: 'اعتداء على مواطن وتهديده', status: 'claimed', assigned: { id: 42, name: 'Rayy' }, createdAt: now - 4000, hasLocation: false },
      { id: 121, reporter: { id: 8, name: 'Yousef' }, target: { id: 44, name: 'Khalid' }, reason: 'قيادة متهورة داخل الأحياء السكنية', status: 'processing', assigned: { id: 23, name: 'Nawaf' }, createdAt: now - 9000, hasLocation: true },
    ] },
    'wanted:list': [
      { id: 9, target: { id: 17, name: 'Hossam', online: true }, job: 'سائق تاكسي', reason: 'مطلوب في قضية سطو مسلح على محل مجوهرات', createdBy: { id: 42, name: 'Rayy' }, createdAt: now - 3600 },
      { id: 8, target: { id: 33, name: 'Turki', online: false }, job: 'بدون وظيفة', reason: 'الهروب من نقطة تفتيش ومقاومة رجال الأمن', createdBy: { id: 23, name: 'Nawaf' }, createdAt: now - 86400 },
      { id: 6, target: { id: 51, name: 'Majed', online: true }, job: 'ميكانيكي', reason: 'تهريب ممنوعات', createdBy: { id: 20, name: 'Saad' }, createdAt: now - 172800 },
    ],
    'affairs:overview': { tiles: ['recruit', 'broadcastOfficers', 'broadcastCitizens', 'recall', 'monitor', 'vacationBalance', 'officerInquiry', 'resetAttendance', 'resetFines', 'resetData', 'statistics'], scope: ['الأمن العام', 'المرور'], stats: { officers: 48, online: 21, onDuty: 14, reports: 4, wanted: 3, prisoners: 6 }, resetData: { attendance: true, fines: true, jails: true, reports: true, impounds: true }, broadcastMax: 300, vacationMax: 60 },
    'affairs:officers': officers,
    'affairs:players': names.map((n, i) => ({ user_id: 10 + i * 4, name: n, rank: i % 3 === 0 ? 'ضابط أمن عام' : '', sectorLabel: i % 3 === 0 ? 'الأمن العام' : '' })),
    'affairs:ranks': [{ key: 'Interior.PublicSecurity', label: 'وزارة الداخلية — الأمن العام', ranks: [{ group: 'ps_deputy', label: 'نائب قائد الأمن العام' }, { group: 'ps_officer', label: 'ضابط أمن عام' }, { group: 'ps_patrol', label: 'دورية أمن عام' }] }, { key: 'Interior.Traffic', label: 'وزارة الداخلية — المرور', ranks: [{ group: 'traffic_commander', label: 'قائد المرور' }, { group: 'traffic_officer', label: 'رجل مرور' }] }],
    'affairs:top': names.map((n, i) => ({ position: i + 1, user_id: 12 + i * 5, name: n, rank: 'ضابط أمن عام', sectorLabel: i % 3 === 1 ? 'المرور' : 'الأمن العام', attendance: 360000 - i * 30000, fines: 90 - i * 7, score: Math.round((100 - i * 8.7) * 10) / 10 })),
    'affairs:officer': { user_id: 17, name: 'Hossam', avatar: null, rank: 'ضابط أمن عام', sectorLabel: 'الأمن العام', ministryLabel: 'وزارة الداخلية', online: true, onDuty: true, code: 'P-07', attendance: 212400, session: 3120, fines: 64, jails: 18, reports: 11, impounds: 5, vacationBalance: 9, vacation: { active: false }, lastClockIn: now - 3120, lastClockOut: now - 90000, actions: { dismiss: true, monitor: true, vacationBalance: true, vacationBreak: false, resetAttendance: true, resetFines: true, resetData: true } },
  };
  return `window.Evora = { devPost: async (name, payload) => {
    const DATA = ${JSON.stringify(data)};
    if (name === 'rpc') { const d = DATA[payload.name]; return d !== undefined ? { ok: true, data: d } : { ok: true, data: true }; }
    return { ok: true };
  } };`;
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ executablePath: EXE });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.addInitScript(mockScript());
  await page.goto('file://' + ROOT);
  await page.addStyleTag({ content: 'html{background:radial-gradient(1200px 700px at 30% 30%,#2c3e50,#0b1016 70%) !important;}' });
  const post = (action, data) => page.evaluate(([a, d]) => window.postMessage({ action: a, data: d }, '*'), [action, data]);
  const shot = async (name, wait) => { await page.waitForTimeout(wait || 700); await page.screenshot({ path: path.join(OUT, name + '.png') }); console.log('shot', name); };

  await post('init', INIT);
  await post('state', { military: true, onDuty: true });
  await post('ipad:open', { tab: 'office' });
  await shot('01-ipad-office', 1200);
  await page.click('[data-tab="online"]');
  await shot('02-ipad-online');
  await page.click('[data-tab="reports"]');
  await shot('03-ipad-reports');
  await page.click('[data-tab="wanted"]');
  await shot('04-ipad-wanted');
  await page.click('[data-tab="affairs"]');
  await shot('05-ipad-affairs');
  await page.click('.tile >> nth=0');
  await page.waitForTimeout(500);
  await page.click('.picker-row >> nth=1');
  await page.click('.chip-btn >> nth=1');
  await shot('06-affairs-recruit');
  await page.click('.sub-head .btn');
  await page.waitForTimeout(400);
  await page.click('.tile >> nth=6');
  await page.waitForTimeout(500);
  await page.click('.picker-row >> nth=0');
  await shot('07-affairs-officer', 900);
  await page.click('.sub-head .btn');
  await page.waitForTimeout(400);
  await page.click('.tile >> nth=10');
  await shot('08-affairs-top10', 900);
  await page.click('[data-tab="office"]');
  await page.waitForTimeout(400);
  await page.click('.vac-idle .btn');
  await shot('09-ipad-vacation-modal');
  await post('ipad:close', {});

  await post('jail:show', { name: 'السجن المركزي', remaining: 1477, total: 1800, reason: 'سرقة' });
  await post('broadcast', { kind: 'officers', title: 'تعميم عسكري', message: 'على جميع الوحدات التوجه إلى البنك المركزي فوراً، يوجد بلاغ سطو مسلح.', sender: 'Rayy — قائد الأمن العام', duration: 30, style: INIT.broadcast });
  await post('confirm:show', { id: 'x1', title: 'مخالفة', message: 'العسكري Rayy | ID: 42 يريد تحرير مخالفة بحقك.', details: [['التصنيف', 'مخالفات مرورية'], ['المخالفة', 'تجاوز السرعة'], ['المبلغ', '$1,500']], timeout: 30, accept: 'F5', reject: 'F6', icon: 'fine' });
  await post('hint', { key: 'E', text: 'سداد المخالفات' });
  await shot('10-hud-broadcast-confirm-jail', 1000);
  await post('confirm:hide', {});
  await post('hint:hide', {});

  await post('idcard:show', { name: 'Hossam', user_id: 17, avatar: null, job: 'سائق تاكسي', title: 'بطاقة الهوية الوطنية', country: 'المملكة العربية السعودية', duration: 30 });
  await post('wanted:alert', { id: 9, name: 'Hossam', user_id: 17, reason: 'مطلوب في قضية سطو مسلح', quickOpen: { enabled: true, label: 'G', seconds: 30 } });
  await post('toast', { message: 'تم تسجيل دخولك للخدمة.', kind: 'success', duration: 30 });
  await post('toast', { message: 'بلاغ جديد #128: Hossam | ID: 17 — سرقة سيارة', kind: 'warning', duration: 30 });
  await shot('11-idcard-wanted-toasts', 1200);
  await page.evaluate(() => { document.getElementById('broadcasts').replaceChildren(); document.getElementById('idcard-layer').classList.add('hidden'); });

  await post('panel:open', { kind: 'citizen', title: 'استعلام عن مواطن', data: { user_id: 17, name: 'Hossam', online: true, job: 'سائق تاكسي', avatar: null, fines: { count: 2, total: 4500, list: [{ id: 3, category: 'مرورية', label: 'تجاوز السرعة', amount: 1500, officer: { id: 42, name: 'Rayy' }, createdAt: Date.now() / 1000 - 5000 }, { id: 5, category: 'عامة', label: 'إزعاج عام', amount: 3000, officer: { id: 23, name: 'Nawaf' }, createdAt: Date.now() / 1000 - 90000 }] }, wanted: { active: true, reason: 'مطلوب في قضية سطو مسلح', by: 'Rayy', createdAt: Date.now() / 1000 - 3600 }, jailed: false } });
  await shot('12-panel-citizen');
  await post('panel:open', { kind: 'finePay', title: 'المخالفات', data: { count: 2, total: 4500, list: [{ id: 3, category: 'مرورية', label: 'تجاوز السرعة', amount: 1500, officer: { id: 42, name: 'Rayy' }, createdAt: Date.now() / 1000 - 5000, status: 'unpaid' }, { id: 5, category: 'عامة', label: 'إزعاج عام', amount: 3000, officer: { id: 23, name: 'Nawaf' }, createdAt: Date.now() / 1000 - 90000, status: 'unpaid' }] } });
  await shot('13-panel-finepay');
  await post('panel:open', { kind: 'vehicle', title: 'تفتيش مركبة', data: { plate: 'P 123ABC', model: 'sultan', owner: { id: 17, name: 'Hossam' }, token: 't', canSeize: true, items: [{ item: 'meth', label: 'ميث', amount: 3, contraband: true }, { item: 'bandage', label: 'ضماد', amount: 1 }, { item: 'water', label: 'ماء', amount: 4 }] } });
  await shot('14-panel-vehicle');
  await post('panel:close', {});

  await post('menu:open', { token: 1, title: 'الشرطة', subtitle: 'قائد الأمن العام • الأمن العام', back: false, items: ['القائمة العسكرية', 'تسجيل الخروج', 'استعلام عن مواطن', 'تعميم بلاغ', 'المخالفات', 'السجن', 'خيارات الميدان', 'الأدوات الأمنية', 'استعلامات', 'حجز المركبات', 'الحواجز'].map((l) => ({ label: l, description: '' })) });
  await post('dialog:open', { id: 1, title: 'إبلاغ عن مجرم', fields: [{ key: 'id', label: 'رقم هوية اللاعب (ID)', type: 'number' }, { key: 'reason', label: 'السبب', type: 'textarea' }] });
  await shot('15-menu-dialog');
  await post('dialog:close', {});
  await post('menu:close', {});
  await post('jail:hide', {});

  await post('spectate:show', { name: 'Hossam', id: 17, kind: 'officer', key: 'BACKSPACE' });
  await post('progress:start', { label: 'تنظيف الساحة', duration: 20 });
  await post('skillcheck:start', { checks: 1, speed: 1, zone: 0.22, key: 'E' });
  await post('alert:status', { active: true, label: 'وسط المدينة' });
  await shot('16-spectate-progress-skill', 900);

  await browser.close();
  if (errors.length) {
    console.error('NUI errors:\n' + errors.join('\n'));
    process.exit(1);
  }
  console.log('no NUI errors');
}

main().catch((e) => { console.error(e); process.exit(1); });
