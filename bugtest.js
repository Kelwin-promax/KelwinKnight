// Testes focados nos bugs 2 (queda em buracos) e 3 (delay do ataque).
const fs = require('fs'), path = require('path'), vm = require('vm');
const dir = __dirname;
let code = /<script>([\s\S]*)<\/script>/.exec(fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8'))[1];
code = code.replace('buildSprites();\ncv.focus();',
  'globalThis.__D = {loadLevel, S, p, LEVELS, VH};\nbuildSprites();\ncv.focus();');

const noopCtx = new Proxy({}, { get(t,k){ if(k==='canvas') return {width:960,height:540};
  if(k==='createLinearGradient'||k==='createRadialGradient'||k==='createPattern') return ()=>({addColorStop(){}});
  if(!(k in t)) t[k]=()=>{}; return t[k]; }, set(){return true;} });
function mkEl(){ const L={}; const el={className:'',hidden:false,width:960,height:540,
  classList:{_s:new Set(),add(c){this._s.add(c)},remove(c){this._s.delete(c)},contains(c){return this._s.has(c)}},
  style:{},focus(){},blur(){},getContext:()=>noopCtx,addEventListener(t,f){(L[t]||=[]).push(f)},_fire(){}};
  let tc=''; Object.defineProperty(el,'textContent',{get:()=>tc,set:v=>{tc=String(v)}}); return el; }
const GL={}; let rafCb=null, now=0;
const sb={document:{getElementById:()=>mkEl(),createElement:()=>mkEl()},
  addEventListener(t,f){(GL[t]||=[]).push(f)},
  performance:{now:()=>now},requestAnimationFrame(cb){rafCb=cb;return 1},
  Math,Object,Set,Array,JSON,console,Number,String,Boolean,Error,Symbol,isNaN};
sb.window=sb; sb.globalThis=sb; sb.window.matchMedia=()=>({matches:false});
vm.createContext(sb); vm.runInContext(code, sb, {filename:'game.js'});

const D = sb.__D;
const kd = k => (GL.keydown||[]).forEach(f => f({key:k, preventDefault(){}}));
const ku = k => (GL.keyup||[]).forEach(f => f({key:k, preventDefault(){}}));
const step = () => { now += 1000/60; const cb = rafCb; rafCb = null; cb(now); };

let fails = 0;
const check = (label, cond, extra) => {
  console.log((cond ? '  ok  ' : ' FALHA ') + label + (extra ? '  [' + extra + ']' : ''));
  if (!cond) fails++;
};

// ---------------------------------------------------------------- bug 2
console.log('=== bug 2: inimigos não caem em buracos ===');
const PITS = [
  { lvl: 1, playerX: 900 },   // nível 2: vão 520..620, jogador do outro lado
  { lvl: 2, playerX: 1300 },  // nível 3: dois vãos
  { lvl: 3, playerX: 1500 },  // nível 4
  { lvl: 2, playerX: 60 },    // puxa os inimigos para o outro sentido
  { lvl: 3, playerX: 60 }
];

for (const c of PITS) {
  D.loadLevel(c.lvl, false);
  D.p.x = c.playerX; D.p.y = 400; D.p.vx = 0; D.p.vy = 0;
  const start = D.S.enemies.length;
  let fell = 0, minY = 0;

  for (let f = 0; f < 60 * 20; f++) {
    D.p.hp = D.p.maxHp; D.p.invuln = 99;      // jogador imortal e parado
    D.p.x = c.playerX; D.p.vx = 0;
    for (const e of D.S.enemies) if (e.y > minY) minY = e.y;
    for (const e of D.S.enemies) if (e.y > D.VH) fell++;
    step();
  }
  const alive = D.S.enemies.length;
  check('nível ' + (c.lvl + 1) + ' (jogador em x=' + c.playerX + '): nenhum inimigo caiu',
        fell === 0 && alive === start,
        alive + '/' + start + ' vivos, y máx atingido ' + minY.toFixed(0));
}

// Prova que ele avança e trava na beirada, e não que ficou parado longe:
// o jogador precisa estar dentro do alcance de aggro (grunt = 360px).
D.loadLevel(1, false);
const alvoPit = D.S.enemies[0];
const xInicial = alvoPit.x;
D.p.x = 700; D.p.y = 400;
for (let f = 0; f < 60 * 8; f++) { D.p.x = 700; D.p.invuln = 99; step(); }
const e0 = D.S.enemies[0];
check('inimigo perseguiu e parou na beirada do vão (chão acaba em 520)',
      e0 && e0.alert && e0.x > xInicial + 20 && e0.x < 500,
      e0 ? 'de x=' + xInicial.toFixed(0) + ' para x=' + e0.x.toFixed(0) + ', alerta=' + e0.alert : 'sumiu');

// ---------------------------------------------------------------- bug 3
console.log('\n=== bug 3: hitbox ativa no 1º frame após J ===');
D.loadLevel(0, false);
D.S.enemies.length = 0;
D.S.enemies.push(...[]);
D.loadLevel(0, false);
const alvo = D.S.enemies[0];
D.p.x = 100; D.p.y = 430; D.p.vx = 0; D.p.vy = 0; D.p.facing = 1;
alvo.x = 132; alvo.y = 436; alvo.vx = 0; alvo.stun = 99; alvo.alert = false;
const hpAntes = alvo.hp;
['a','d',' ','shift','j'].forEach(ku);
kd('j');
step();                                        // exatamente UM frame
check('inimigo levou dano no mesmo frame do input', alvo.hp < hpAntes,
      'vida ' + hpAntes + ' -> ' + alvo.hp);

// cadência entre golpes
D.loadLevel(0, false);
const alvo2 = D.S.enemies[0];
D.p.x = 100; D.p.y = 430; D.p.facing = 1;
alvo2.x = 132; alvo2.y = 436; alvo2.stun = 999; alvo2.hp = 99999; alvo2.alert = false;
let hits = 0, lastHp = alvo2.hp, firstHit = -1, secondHit = -1;
for (let f = 0; f < 60; f++) {
  alvo2.x = 132; alvo2.vx = 0; alvo2.stun = 999;
  ku('j'); kd('j');                            // martelando a tecla
  step();
  if (alvo2.hp < lastHp) {
    hits++; lastHp = alvo2.hp;
    if (firstHit < 0) firstHit = f; else if (secondHit < 0) secondHit = f;
  }
}
const cadencia = secondHit > 0 ? ((secondHit - firstHit) / 60 * 1000) : -1;
check('primeiro acerto no frame 0', firstHit === 0, 'frame ' + firstHit);
check('cadência entre golpes ~310ms', cadencia > 280 && cadencia < 340,
      cadencia.toFixed(0) + 'ms (' + hits + ' acertos em 1s)');

console.log('\n' + (fails === 0 ? 'TODOS OS TESTES PASSARAM' : fails + ' FALHA(S)'));
process.exit(fails ? 1 : 0);
