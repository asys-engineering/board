// Board @ ASYS (Supabase sürümü) — Playwright testleri. supabase-js yerine şemayla aynı kuralları uygulayan bellek-içi mock kullanır.
const { chromium } = require('playwright');
const fs = require('fs'); const path = require('path');
const DIR = __dirname; const SITE = path.join(DIR, '..');

const MOCK = `
window.supabase={createClient:()=>{
  const T=window.__db={people:[{id:'p-huseyin',name:'Hüseyin Özkan',role:'Genel Müdür',active:true},{id:'p2',name:'Ali Kaya',role:'Elektrik Şefi',active:true},{id:'p3',name:'Дулат Омаров',role:'Прораб',active:true}],
    pins:{'p-huseyin':'9001','p2':'9002','p3':'9003'},pm:'test-pm-pass',settings:[{key:'site',value:{project:'Wildberries Almaty'}}],items:[],sessions:{}};
  const seed=window.__seed||[];T.items.push(...seed);
  const err=m=>({data:null,error:{message:m}});const ok=d=>({data:d,error:null});
  const sess=t=>{const s=T.sessions[t];if(!s)throw new Error('not_logged_in');return s;};
  const now=()=>new Date().toISOString();
  const rpc={
    board_login:({p_person,p_pin})=>{const p=T.people.find(x=>x.id===p_person&&x.active!==false);if(!p)throw new Error('no_person');if(T.pins[p_person]!==p_pin)throw new Error('bad_pin');const tok='t'+Math.random().toString(36).slice(2);T.sessions[tok]={person:p_person,role:'site'};return {token:tok,person:p_person,role:'site'};},
    board_pm_login:({p_token,p_pass})=>{const s=sess(p_token);if(p_pass!==T.pm)throw new Error('bad_pass');s.role='pm';return {person:s.person,role:'pm'};},
    board_pm_logout:({p_token})=>{sess(p_token).role='site';return null;},
    board_logout:({p_token})=>{delete T.sessions[p_token];return null;},
    board_me:({p_token})=>{const s=T.sessions[p_token];return s?{person:s.person,role:s.role}:null;},
    board_create_item:({p_token,p_title,p_descr})=>{const s=sess(p_token);if(!p_title.trim())throw new Error('title_required');const no=T.items.reduce((m,x)=>Math.max(m,x.no),0)+1;const nm=T.people.find(x=>x.id===s.person)?.name||'';const r={id:'i'+no,no,title:p_title.trim(),descr:p_descr||'',priority:'normal',status:'acik',by_person:s.person,by_name:nm,at:now(),assignee:'',due:'',decision:'',meeting:'',closed_at:'',done_at:'',done_by:'',comments:[],updated_at:now()};T.items.push(r);return r;},
    board_update_item:({p_token,p_id,p_patch})=>{const s=sess(p_token);const cur=T.items.find(x=>x.id===p_id);if(!cur)throw new Error('no_item');const P=p_patch;
      if(s.role==='pm'){const map={title:'title',desc:'descr',priority:'priority',status:'status',assignee:'assignee',due:'due',decision:'decision',meeting:'meeting',closedAt:'closed_at',doneAt:'done_at',doneBy:'done_by'};for(const k in map)if(P[k]!=null)cur[map[k]]=P[k];cur.updated_at=now();return cur;}
      const ns=P.status;if(ns!=null&&ns!==cur.status){if(!(cur.assignee===s.person||cur.by_person===s.person))throw new Error('not_allowed');
        if(ns==='yapildi'&&['acik','gorusuldu','cozumde'].includes(cur.status)){cur.status='yapildi';cur.done_at=now();cur.done_by=s.person;cur.updated_at=now();return cur;}
        if(cur.status==='yapildi'&&['acik','gorusuldu'].includes(ns)){cur.status=ns;cur.done_at='';cur.done_by='';return cur;}throw new Error('not_allowed');}
      if('title' in P||'desc' in P){if(!(cur.by_person===s.person&&cur.status==='acik'))throw new Error('not_allowed');if(P.title!=null)cur.title=P.title;if(P.desc!=null)cur.descr=P.desc;return cur;}
      return cur;},
    board_add_comment:({p_token,p_id,p_text})=>{const s=sess(p_token);const cur=T.items.find(x=>x.id===p_id);if(!cur)throw new Error('no_item');cur.comments=[...cur.comments,{by:s.person,byName:T.people.find(x=>x.id===s.person)?.name||'',at:now(),text:p_text.trim()}];return cur;},
    board_delete_item:({p_token,p_id})=>{const s=sess(p_token);if(s.role!=='pm')throw new Error('pm_required');T.items=T.items.filter(x=>x.id!==p_id);return null;},
    board_upsert_person:({p_token,p_id,p_name,p_role,p_active,p_pin})=>{const s=sess(p_token);if(s.role!=='pm')throw new Error('pm_required');const id=p_id||('p'+Math.random().toString(36).slice(2,8));let p=T.people.find(x=>x.id===id);if(!p){p={id};T.people.push(p);}Object.assign(p,{name:p_name.trim(),role:p_role||'',active:p_active!==false});if(p_pin&&p_pin.length>=4)T.pins[id]=p_pin;return p;},
    board_set_pm_password:({p_token,p_pass})=>{const s=sess(p_token);if(s.role!=='pm')throw new Error('pm_required');if(p_pass.length<4)throw new Error('too_short');T.pm=p_pass;return null;},
    board_set_setting:({p_token,p_key,p_value})=>{const s=sess(p_token);if(s.role!=='pm')throw new Error('pm_required');const r=T.settings.find(x=>x.key===p_key);if(r)r.value=p_value;else T.settings.push({key:p_key,value:p_value});return null;}
  };
  return {
    rpc:async(n,a)=>{try{if(!rpc[n])throw new Error('no_fn '+n);return ok(JSON.parse(JSON.stringify(rpc[n](a))));}catch(e){return err(e.message);}},
    from:(tbl)=>{const q={_f:null,select(){return q;},eq(k,v){q._f=[k,v];return q;},then(res){let rows=T[tbl];if(q._f)rows=rows.filter(r=>r[q._f[0]]===q._f[1]);res(ok(JSON.parse(JSON.stringify(rows))));}};return q;},
    channel:()=>{const c={on(){return c;},subscribe(cb){window.__sub=cb;cb('SUBSCRIBED');return c;}};return c;}
  };}};
`;

const errors = []; let shots = 0;
async function run(name, opts, fn) {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: opts.mobile ? { width: 390, height: 800 } : { width: 1200, height: 900 }, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('console', m => { if (m.type() === 'error' && !/ERR_TUNNEL|net::|Failed to load resource/.test(m.text())) errors.push(`[${name}] console: ${m.text()}`); });
  page.on('pageerror', e => errors.push(`[${name}] pageerror: ${e.message}`));
  await page.route('https://cdn.jsdelivr.net/**', r => r.fulfill({ body: MOCK, contentType: 'application/javascript' }));
  await page.route('https://cdnjs.cloudflare.com/ajax/libs/pdfmake/**', r => { const f = r.request().url().endsWith('vfs_fonts.js') ? 'vfs_fonts.js' : 'pdfmake.min.js'; r.fulfill({ path: path.join(DIR, '..', 'node_modules/pdfmake/build', f), contentType: 'application/javascript' }); });
  await page.route('https://fonts.googleapis.com/**', r => r.fulfill({ body: '', contentType: 'text/css' }));
  await page.route('**/config.js', r => r.fulfill({ body: 'window.BOARD_CONFIG={url:"https://example.supabase.co",key:"test"};', contentType: 'application/javascript' }));
  if (opts.seed) await page.addInitScript(seed => { window.__seed = seed; }, opts.seed);
  if (opts.ls) await page.addInitScript(ls => { for (const k in ls) localStorage.setItem('asys-saha:' + k, ls[k]); }, opts.ls);
  await page.goto('file://' + path.join(SITE, 'index.html'));
  await page.waitForTimeout(400);
  try { await fn(page); } catch (e) { errors.push(`[${name}] step: ${e.message}`); await page.screenshot({ path: path.join(DIR, `fail-${name}.png`) }); }
  await browser.close();
}
const item = (id, no, title, st, by, ass, due, extra = {}) => ({ id, no, title, descr: '', priority: 'normal', status: st, by_person: by, by_name: '', at: '2026-11-01T08:00:00Z', assignee: ass, due, decision: '', meeting: '', closed_at: '', done_at: '', done_by: '', comments: [], updated_at: '', ...extra });

(async () => {
  // 1. Fresh site user: login, create, done, edit; PM login; meeting; PDF; settings incl. PIN
  await run('full', {}, async (page) => {
    if (await page.locator('#mWho').isHidden()) throw new Error('login modal not shown');
    await page.locator('#whoPick button', { hasText: 'Ali Kaya' }).click();
    await page.fill('#pinInp', '0000'); await page.click('#pinGo'); await page.waitForTimeout(200);
    if (await page.locator('#pinErr').isHidden()) throw new Error('wrong pin not flagged');
    await page.fill('#pinInp', '9002'); await page.click('#pinGo'); await page.waitForTimeout(300);
    if (!await page.locator('#mWho').isHidden()) throw new Error('login did not close modal');
    if (!/Ali Kaya/.test(await page.locator('#whoami').textContent())) throw new Error('name not shown');
    const tok = await page.evaluate(() => localStorage.getItem('asys-saha:token')); if (!tok) throw new Error('token not stored');
    // create
    await page.click('#fab'); await page.fill('#nTitle', 'Blok 2 ВРУ-2 kablo kanalı eksik'); await page.fill('#nDesc', 'Aks 5-6'); await page.click('#nSave'); await page.waitForTimeout(300);
    if ((await page.locator('.it').count()) !== 1) throw new Error('item not created');
    await page.click('#fab'); await page.fill('#nTitle', 'İkinci'); await page.click('#nSave'); await page.waitForTimeout(300);
    // edit own
    await page.locator('.it', { hasText: 'İkinci' }).click(); await page.waitForTimeout(100);
    if (await page.locator('#dAss').count()) throw new Error('PM box visible to site user');
    await page.click('#dEdit'); await page.fill('#nTitle', 'İkinci (düz.)'); await page.click('#nSave'); await page.waitForTimeout(300);
    if (!(await page.locator('.it', { hasText: 'düz.' }).count())) throw new Error('edit failed');
    // comment
    await page.locator('.it', { hasText: 'düz.' }).click(); await page.fill('#cmText', 'yorum'); await page.click('#cmAdd'); await page.waitForTimeout(300);
    if (!(await page.locator('#cmList .cm').count())) throw new Error('comment missing');
    await page.click('#detClose');
    // done on own
    await page.locator('.it', { hasText: 'düz.' }).locator('.doneBtn').click(); await page.waitForTimeout(300);
    if (!(await page.locator('.it.done').count())) throw new Error('done failed');
    // PM login
    await page.click('#btnPm'); await page.fill('#pmPass', 'x'); await page.click('#pmGo'); await page.waitForTimeout(200);
    if (await page.locator('#pmErr').isHidden()) throw new Error('bad pm pass not flagged');
    await page.fill('#pmPass', 'test-pm-pass'); await page.click('#pmGo'); await page.waitForTimeout(300);
    if (!(await page.locator('#whoami .role.pm').count())) throw new Error('pm login failed');
    // PM assigns in detail
    await page.locator('.it', { hasText: 'kablo' }).click(); await page.waitForTimeout(100);
    await page.selectOption('#dAss', 'p3'); await page.fill('#dDue', '2026-11-10'); await page.selectOption('#dPrio', 'kritik'); await page.fill('#dDec', 'Sipariş'); await page.click('#dSave'); await page.waitForTimeout(300);
    if (!/Görüşüldü/.test(await page.locator('#detBox .st').first().textContent())) throw new Error('assign did not set gorusuldu');
    await page.click('#detClose');
    // meeting
    await page.click('#tabs button[data-tab="toplanti"]'); await page.waitForTimeout(200);
    if (!(await page.locator('.mt').count())) throw new Error('meeting empty');
    if (!(await page.locator('.mt.done').count())) throw new Error('done group missing');
    await page.locator('.mt.done .aKap').first().click(); await page.waitForTimeout(300);
    if (await page.locator('.mt.done').count()) throw new Error('close from meeting failed');
    await page.click('#protoCopy'); await page.waitForTimeout(100);
    const dlP = page.waitForEvent('download', { timeout: 30000 }); await page.click('#protoPdf'); const dl = await dlP;
    if (!dl.suggestedFilename().endsWith('.pdf')) throw new Error('pdf download name');
    // dashboard
    await page.click('#tabs button[data-tab="gosterge"]'); await page.waitForTimeout(200);
    if ((await page.locator('#kpis .kpi').count()) !== 7) throw new Error('kpis');
    // settings: add person with PIN, reset PIN, toggle, change pm pass
    await page.click('#tabs button[data-tab="ayarlar"]'); await page.waitForTimeout(200);
    await page.fill('#pName', 'Yeni Kişi'); await page.fill('#pRole', 'Usta'); await page.click('#addPerson'); await page.waitForTimeout(200);
    if ((await page.locator('#people .person').count()) !== 3) throw new Error('person added without PIN');
    await page.fill('#pPin', '5555'); await page.click('#addPerson'); await page.waitForTimeout(300);
    if ((await page.locator('#people .person').count()) !== 4) throw new Error('person not added');
    await page.locator('#people .person', { hasText: 'Yeni Kişi' }).locator('.pr').click(); await page.fill('#mPinInp', '7777'); await page.click('#mPinGo'); await page.waitForTimeout(300);
    const pins = await page.evaluate(() => window.__db.pins); if (!Object.values(pins).includes('7777')) throw new Error('pin reset failed');
    await page.locator('#people .person', { hasText: 'Yeni Kişi' }).locator('.tg').click(); await page.waitForTimeout(300);
    if (!(await page.locator('#people .person.off').count())) throw new Error('passive failed');
    await page.fill('#newPass', 'yeni1234'); await page.click('#savePass'); await page.waitForTimeout(300);
    if ((await page.evaluate(() => window.__db.pm)) !== 'yeni1234') throw new Error('pm pass change failed');
    const dlP2 = page.waitForEvent('download', { timeout: 30000 }); await page.click('#allPdf'); await dlP2;
    // PM logout, user logout
    await page.click('#btnPm'); await page.waitForTimeout(200); if (await page.locator('#whoami .role.pm').count()) throw new Error('pm logout failed');
    await page.click('#btnWho'); await page.waitForTimeout(300); if (await page.locator('#mWho').isHidden()) throw new Error('logout did not reopen login');
    if (await page.evaluate(() => localStorage.getItem('asys-saha:token'))) throw new Error('token not cleared');
    await page.screenshot({ path: path.join(DIR, 'shot-full.png'), fullPage: true });
  });

  // 2. Session restore + default filter + RU + mobile
  const seed = [item('i1', 1, 'Bana atanan iş', 'gorusuldu', 'p-huseyin', 'p2', '2026-10-20', { priority: 'yuksek' }), item('i2', 2, 'Başkasının işi', 'acik', 'p3', '', '')];
  await run('restore', { seed, mobile: true, ls: { lang: 'ru' } }, async (page) => {
    // login first to get a token, then reload to test restore
    await page.locator('#whoPick button', { hasText: 'Ali Kaya' }).click(); await page.fill('#pinInp', '9002'); await page.click('#pinGo'); await page.waitForTimeout(300);
    const tok = await page.evaluate(() => localStorage.getItem('asys-saha:token'));
    // simulate reload: mock sessions live in page memory, so re-inject session into a fresh page via init script
    await page.evaluate(() => { window.__keep = window.__db.sessions; });
    const sessions = await page.evaluate(() => window.__db.sessions);
    await page.addInitScript(({ tok, sessions }) => { localStorage.setItem('asys-saha:token', tok); window.__restoreSessions = sessions; }, { tok, sessions });
    await page.route('https://cdn.jsdelivr.net/**', r => r.fulfill({ body: MOCK.replace('T.items.push(...seed);', 'T.items.push(...seed);if(window.__restoreSessions)Object.assign(T.sessions,window.__restoreSessions);'), contentType: 'application/javascript' }));
    await page.reload(); await page.waitForTimeout(500);
    if (!await page.locator('#mWho').isHidden()) throw new Error('session not restored');
    if (!/Ali Kaya/.test(await page.locator('#whoami').textContent())) throw new Error('restored name missing');
    if (!(await page.locator('#mineChips .chip.on[data-mine="to"]').count())) throw new Error('default filter not "to me"');
    if ((await page.locator('.it').count()) !== 1) throw new Error('expected 1 assigned item');
    if (!/Открытые/.test(await page.locator('#tabs button[data-tab="liste"] span').first().textContent())) throw new Error('RU not applied');
    if (!(await page.locator('.it .late').count())) throw new Error('late flag missing');
    const sw = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth); if (sw) throw new Error('horizontal scroll on mobile');
    // meeting read-only for site user
    await page.click('#tabs button[data-tab="toplanti"]'); await page.waitForTimeout(200);
    if (await page.locator('.mAss').count()) throw new Error('PM controls visible to site user');
    if (!(await page.locator('.miss').count())) throw new Error('missing-assignee flag absent');
    await page.click('#tabs button[data-tab="liste"]');
    await page.screenshot({ path: path.join(DIR, 'shot-mobile.png'), fullPage: true });
  });

  // 3. Expired token → re-login prompt
  await run('expired', { ls: { token: 'dead', me: 'p2' } }, async (page) => {
    if (await page.locator('#mWho').isHidden()) throw new Error('expired token should show login');
    if (!(await page.locator('#whoami .role').count())) throw new Error('no-login badge missing');
  });

  fs.writeFileSync(path.join(DIR, 'errors.txt'), errors.join('\n'));
  console.log(errors.length ? 'ERRORS:\n' + errors.join('\n') : 'ALL PASS');
})();
