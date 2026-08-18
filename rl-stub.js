// Stub de DOM/Canvas compartilhado pelos testes do roguelike.
// Carrega corte-seco-rl.html num contexto de VM, injetando um hook de debug SÓ
// na cópia em memória — o arquivo publicado não muda.
//
// A leitura normaliza CRLF -> LF de propósito: em checkout Windows com
// core.autocrlf=true o arquivo chega com \r\n e uma âncora escrita com \n
// literal nunca casaria.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ANCHOR = 'cv.focus();\nrequestAnimationFrame(frame);';

const HOOK = `globalThis.__DBG = {
  S, p, FLOORS, TYPES, BOSS, TILE, WALL, FLOOR,
  genDungeon, reachable, solidAt, lineOfSight, startRun, loadFloor, spawnEnemy,
  ATK_RANGE, ATK_ARC, ATK_DMG, DASH_CD, DASH_TIME, DASH_SPEED, MAX_SPEED,
  BLOCK_SPEED, BLOCK_REDUCE, BLOCK_ARC, hurtPlayer
};
`;

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
    classList: {
      _s: new Set(),
      add(c) { this._s.add(c); },
      remove(c) { this._s.delete(c); },
      contains(c) { return this._s.has(c); }
    },
    style: {},
    focus() {}, blur() {},
    getContext: () => noopCtx,
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 960, height: 540 }),
    addEventListener(t, fn) { (listeners[t] ||= []).push(fn); },
    _fire(t, ev) { (listeners[t] || []).forEach(fn => fn(ev || {})); }
  };
  let _tc = '';
  Object.defineProperty(el, 'textContent', {
    get: () => _tc, set: v => { _tc = String(v); }
  });
  return el;
}

// Carrega o jogo e devolve o painel de controle usado pelos testes.
function load() {
  const dir = __dirname;
  const html = fs.readFileSync(path.join(dir, 'corte-seco-rl.html'), 'utf8').replace(/\r\n/g, '\n');
  let code = /<script>([\s\S]*)<\/script>/.exec(html)[1];
  if (!code.includes(ANCHOR)) throw new Error('âncora de injeção não encontrada em corte-seco-rl.html');
  code = code.replace(ANCHOR, HOOK + ANCHOR);

  const els = {};
  for (const id of ['cv','ov','card','ovEyebrow','ovTitle','ovText','ovStats','ovBtn','ovBtn2','stTime','stDmg','stTries']) {
    els[id] = mkEl(id);
  }

  const globalListeners = {};
  let rafCb = null;
  const clock = { now: 0 };

  const sandbox = {
    document: { getElementById: id => els[id] || mkEl(id), createElement: () => mkEl('offscreen') },
    addEventListener(t, fn) { (globalListeners[t] ||= []).push(fn); },
    performance: { now: () => clock.now },
    requestAnimationFrame(cb) { rafCb = cb; return 1; },
    Math, Object, Set, Map, Array, JSON, console, Number, String, Boolean,
    Error, Symbol, isNaN, isFinite, Infinity, NaN, parseInt, parseFloat, Date, Proxy
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.window.matchMedia = () => ({ matches: false });

  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: 'corte-seco-rl.js' });

  const D = sandbox.__DBG;

  const keyDown = k => (globalListeners.keydown || []).forEach(fn => fn({ key: k, preventDefault() {} }));
  const keyUp = k => (globalListeners.keyup || []).forEach(fn => fn({ key: k, preventDefault() {} }));

  const ALL_KEYS = ['a', 'd', 'w', 's', 'shift', 'j', 'k', 'q', 'z', 'l'];
  const held = new Set();
  const press = k => { if (!held.has(k)) { held.add(k); keyDown(k); } };
  const release = k => { if (held.has(k)) { held.delete(k); keyUp(k); } };
  const releaseAll = () => { for (const k of ALL_KEYS) release(k); };

  const FPS = 60, DT = 1 / FPS;
  // Avança exatamente um frame do jogo. Devolve false se o loop parou de
  // agendar (nunca deve acontecer; sinaliza exceção engolida no rAF).
  function step() {
    clock.now += 1000 / FPS;
    const cb = rafCb;
    rafCb = null;
    if (!cb) return false;
    cb(clock.now);
    return true;
  }

  return {
    D, sandbox, els, globalListeners,
    keyDown, keyUp, press, release, releaseAll, held,
    step, DT, FPS, clock,
    overlayOpen: () => els.ov.classList.contains('on'),
    title: () => els.ovTitle.textContent,
    clickPrimary: () => els.ovBtn._fire('click'),
    clickSecondary: () => els.ovBtn2._fire('click')
  };
}

// ---------------------------------------------------------------- asserções
function makeChecker() {
  const state = { failures: 0, total: 0 };
  const check = (label, cond, extra) => {
    state.total++;
    console.log((cond ? '  ok  ' : ' FAIL ') + label + (extra ? '  [' + extra + ']' : ''));
    if (!cond) state.failures++;
    return !!cond;
  };
  return { check, state };
}

// BFS de tiles: devolve o caminho como lista de [tx,ty], ou null.
// Usado pelo bot dos testes — sem isso ele encalha na primeira quina de
// corredor, porque andar em linha reta até o alvo não atravessa parede.
function findPath(map, from, to, FLOOR_ID) {
  const { gw, gh, grid } = map;
  if (from.tx === to.tx && from.ty === to.ty) return [[from.tx, from.ty]];
  const prev = new Map();
  const key = (x, y) => y * gw + x;
  const seen = new Set([key(from.tx, from.ty)]);
  let q = [[from.tx, from.ty]];

  while (q.length) {
    const next = [];
    for (const [x, y] of q) {
      for (const [nx, ny] of [[x+1,y],[x-1,y],[x,y+1],[x,y-1]]) {
        if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
        if (grid[ny][nx] !== FLOOR_ID) continue;
        const k = key(nx, ny);
        if (seen.has(k)) continue;
        seen.add(k);
        prev.set(k, [x, y]);
        if (nx === to.tx && ny === to.ty) {
          const path = [[nx, ny]];
          let cur = [x, y];
          while (!(cur[0] === from.tx && cur[1] === from.ty)) {
            path.push(cur);
            cur = prev.get(key(cur[0], cur[1]));
            if (!cur) return null;
          }
          path.push([from.tx, from.ty]);
          return path.reverse();
        }
        next.push([nx, ny]);
      }
    }
    q = next;
  }
  return null;
}

module.exports = { load, makeChecker, findPath, mkEl, noopCtx };
