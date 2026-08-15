// Harness headless: stub de DOM/Canvas + bot que joga, para validar a curva de dificuldade.
// Injeta um hook de debug SÓ na cópia carregada aqui — o arquivo publicado não muda.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const dir = __dirname;
const html = fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8');
let code = /<script>([\s\S]*)<\/script>/.exec(html)[1];

const anchor = 'cv.focus();\nrequestAnimationFrame(frame);';
if (!code.includes(anchor)) throw new Error('âncora de injeção não encontrada');
code = code.replace(anchor, 'globalThis.__DBG = {S, p, LEVELS, TYPES, BOSS};\n' + anchor);

const mkGradient = () => ({ addColorStop() {} });
const noopCtx = new Proxy({}, {
  get(t, k) {
    if (k === 'canvas') return { width: 960, height: 540 };
    if (k === 'createLinearGradient' || k === 'createRadialGradient' || k === 'createPattern') return mkGradient;
    if (!(k in t)) t[k] = () => {};
    return t[k];
  },
  set() { return true; }
});

function mkEl(id) {
  const listeners = {};
  const el = {
    id, className: '', hidden: false, width: 960, height: 540,
    classList: { _s: new Set(), add(c) { this._s.add(c); }, remove(c) { this._s.delete(c); }, contains(c) { return this._s.has(c); } },
    style: {},
    focus() {}, blur() {},
    getContext: () => noopCtx,
    addEventListener(t, fn) { (listeners[t] ||= []).push(fn); },
    _fire(t, ev) { (listeners[t] || []).forEach(fn => fn(ev || {})); }
  };
  let _tc = '';
  Object.defineProperty(el, 'textContent', { // o DOM real converte para string
    get: () => _tc, set: v => { _tc = String(v); }
  });
  return el;
}

const els = {};
for (const id of ['cv','ov','card','ovEyebrow','ovTitle','ovText','ovStats','ovBtn','ovBtn2','stTime','stDmg','stTries']) els[id] = mkEl(id);

const globalListeners = {};
let rafCb = null, now = 0;

const sandbox = {
  document: { getElementById: id => els[id] || mkEl(id), createElement: () => mkEl('offscreen') },
  addEventListener(t, fn) { (globalListeners[t] ||= []).push(fn); },
  performance: { now: () => now },
  requestAnimationFrame(cb) { rafCb = cb; return 1; },
  Math, Object, Set, Array, JSON, console, Number, String, Boolean, Error, Symbol, isNaN,
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.window.matchMedia = () => ({ matches: false });

vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: 'game.js' });

const D = sandbox.__DBG;
const keyDown = k => (globalListeners.keydown || []).forEach(fn => fn({ key: k, preventDefault() {} }));
const keyUp   = k => (globalListeners.keyup   || []).forEach(fn => fn({ key: k, preventDefault() {} }));
const ALL = ['a','d','w',' ','shift','j'];
const held = new Set();
const press = k => { if (!held.has(k)) { held.add(k); keyDown(k); } };
const releaseAll = () => { for (const k of ALL) if (held.has(k)) { held.delete(k); keyUp(k); } };

const overlayOpen = () => els.ov.classList.contains('on');
const title = () => els.ovTitle.textContent;
const clickPrimary = () => els.ovBtn._fire('click');

// ------------------------------------------------------------------ bot
let retreat = 0, runup = 0, jumpDir = 1, commitT = 0;
function solidBelow(x, y) {
  return D.S.plats.some(pl => x > pl.x && x < pl.x + pl.w && y > pl.y - 6 && y < pl.y + pl.h);
}
function nearest() {
  const S = D.S, p = D.p;
  if (S.boss) return S.boss;
  let best = null, bd = Infinity;
  for (const e of S.enemies) {
    const d = Math.abs((e.x + e.w/2) - (p.x + p.w/2));
    if (d < bd) { bd = d; best = e; }
  }
  return best;
}
function bot(dt) {
  const S = D.S, p = D.p;
  releaseAll();
  if (S.mode !== 'play') return;
  const t = nearest();
  if (!t) return;
  const dx = (t.x + t.w/2) - (p.x + p.w/2);
  const dy = (t.y + t.h/2) - (p.y + p.h/2);
  const adx = Math.abs(dx), dir = Math.sign(dx) || 1;

  // esquiva a investida do chefe com dash
  if (S.boss && (S.boss.state === 'charge' || S.boss.state === 'tell-charge') && adx < 260) {
    press('shift'); press(dir > 0 ? 'a' : 'd');
    return;
  }
  // Salto de vão comprometido: mantém direção e botão até tocar o chão. Sem
  // isso o bot re-mira no inimigo mais próximo no meio do pulo, inverte e cai.
  if (commitT > 0) {
    commitT -= dt;
    press(' ');
    press(jumpDir > 0 ? 'd' : 'a');
    if (p.onGround && commitT < 1.05) commitT = 0;
    return;
  }

  // vão à frente: recua para pegar impulso e só então salta
  const edge = dir > 0 ? p.x + p.w : p.x;
  const gap = p.onGround && !solidBelow(edge + dir * 30, p.y + p.h + 6);
  if (runup > 0) { runup -= dt; press(dir > 0 ? 'a' : 'd'); return; }
  if (gap) {
    if (p.vx * dir > 200) { commitT = 1.2; jumpDir = dir; press(' '); press(dir > 0 ? 'd' : 'a'); return; }
    runup = .30; press(dir > 0 ? 'a' : 'd'); return;
  }

  if (retreat > 0) { retreat -= dt; press(dir > 0 ? 'a' : 'd'); return; }

  if (adx < 58 && Math.abs(dy) < 36) {   // no alcance: golpeia e recua
    press('j');
    retreat = .38;
    return;
  }
  press(dir > 0 ? 'd' : 'a');
  if (dy < -34 && p.onGround) press(' ');  // alvo acima
}

// ------------------------------------------------------------------ run
const FPS = 60, DT = 1 / FPS;
let pitFalls = 0;
function frame() {
  bot(DT);
  now += 1000 / FPS;
  const cb = rafCb; rafCb = null;
  if (!cb) throw new Error('loop parou de agendar frames');
  cb(now);
  for (const e of D.S.enemies) if (e.y > 540 && !e._fell) { e._fell = true; pitFalls++; }
}

let failures = 0;
const check = (label, cond, extra) => {
  console.log((cond ? '  ok  ' : ' FAIL ') + label + (extra ? '  [' + extra + ']' : ''));
  if (!cond) failures++;
};

console.log('=== smoke ===');
check('overlay de título aberto', overlayOpen(), title());
check('título correto', title() === 'Corte Seco', title());
clickPrimary();
check('começa fechando o overlay', !overlayOpen());

console.log('\n=== playthrough (bot) ===');
const report = [];
let levelStart = { deaths: 0, dmg: 0, time: 0 };
let guard = 0;

for (let lvl = 1; lvl <= 5; lvl++) {
  let deaths = 0, dmg = 0, time = 0, resolved = false;

  for (let attempt = 0; attempt < 12 && !resolved; attempt++) {
    let frames = 0;
    while (!overlayOpen() && frames < 60 * 180) { frame(); frames++; guard++; }
    if (frames >= 60 * 180) { check('nível ' + lvl + ' não travou', false, 'timeout de 180s'); break; }
    time += D.S.stats.time;
    dmg += D.S.stats.dmg;
    if (/falhou/.test(title())) { deaths++; clickPrimary(); }
    else { resolved = true; }
  }

  const label = /Protótipo|Executor|caiu/.test(title()) ? 'vitória final' : title();
  check('nível ' + lvl + ' concluído pelo bot', resolved, label);
  report.push({ lvl, deaths, dmg, time: time.toFixed(1) });
  if (!resolved) break;

  if (lvl === 1) {
    check('stats do nível 1 preenchidas', els.ovStats.hidden === false && els.stTime.textContent.endsWith('s') && els.stTries.textContent === '1',
          els.stTime.textContent + ' · dano ' + els.stDmg.textContent + ' · ' + els.stTries.textContent + 'ª tentativa');
    check('nível 1 sem mortes (tutorial seguro)', deaths === 0, deaths + ' morte(s)');
  }
  if (lvl < 5) { clickPrimary(); check('nível ' + (lvl+1) + ' carregou', !overlayOpen()); }
}

console.log('\n=== curva medida (run do bot) ===');
console.log(' nível | tempo   | dano sofrido | mortes');
for (const r of report) {
  console.log('   ' + r.lvl + '   | ' + (r.time + 's').padEnd(7) + ' | ' + String(r.dmg).padEnd(12) + ' | ' + r.deaths);
}

// a curva deve subir de 1 para 4 no dano acumulado
if (report.length >= 4) {
  check('dano do nível 1 é o menor', report[0].dmg <= Math.min(...report.slice(1, 4).map(r => r.dmg)),
        report.map(r => r.dmg).join(' → '));
}

check('nenhum inimigo caiu em buraco durante todo o playthrough', pitFalls === 0, pitFalls + ' queda(s)');

console.log('\n=== pausa e reinício ===');
if (overlayOpen()) clickPrimary();
keyDown('p'); keyUp('p');
const before = D.S.mode;
frame();
check('P pausa', D.S.mode === 'paused', before + ' → ' + D.S.mode);
keyDown('p'); keyUp('p'); frame();
check('P despausa', D.S.mode === 'play', D.S.mode);

console.log('\n' + (failures === 0 ? 'TODOS OS TESTES PASSARAM' : failures + ' FALHA(S)') + '  (' + guard + ' frames simulados)');
process.exit(failures ? 1 : 0);
