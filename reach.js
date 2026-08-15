// Verificador de alcançabilidade: usa a física real do jogo para decidir se
// cada plataforma suspensa pode ser atingida a partir de alguma superfície.
const fs = require('fs'), path = require('path'), vm = require('vm');
const dir = __dirname;
let code = /<script>([\s\S]*)<\/script>/.exec(fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8'))[1];
code = code.replace('buildSprites();\ncv.focus();',
  'globalThis.__C = {LEVELS, JUMP_V, GRAVITY, MAX_SPEED, VH, p};\nbuildSprites();\ncv.focus();');

const noopCtx = new Proxy({}, { get(t,k){ if(k==='canvas') return {width:960,height:540};
  if(k==='createLinearGradient'||k==='createRadialGradient'||k==='createPattern') return ()=>({addColorStop(){}});
  if(!(k in t)) t[k]=()=>{}; return t[k]; }, set(){return true;} });
function mkEl(){ const L={}; const el={className:'',hidden:false,width:960,height:540,
  classList:{_s:new Set(),add(c){this._s.add(c)},remove(c){this._s.delete(c)},contains(c){return this._s.has(c)}},
  style:{},focus(){},blur(){},getContext:()=>noopCtx,addEventListener(t,f){(L[t]||=[]).push(f)},_fire(){}};
  let tc=''; Object.defineProperty(el,'textContent',{get:()=>tc,set:v=>{tc=String(v)}}); return el; }
const els=new Proxy({},{get:()=>mkEl()});
const sb={document:{getElementById:()=>mkEl(),createElement:()=>mkEl()},addEventListener(){},
  performance:{now:()=>0},requestAnimationFrame(){return 1},Math,Object,Set,Array,JSON,console,Number,String,Boolean,Error,Symbol,isNaN};
sb.window=sb; sb.globalThis=sb; sb.window.matchMedia=()=>({matches:false});
vm.createContext(sb); vm.runInContext(code, sb, {filename:'game.js'});

const { LEVELS, JUMP_V, GRAVITY, MAX_SPEED, p } = sb.__C;
const PW = 26, PH = 40;
const maxRise = (JUMP_V * JUMP_V) / (2 * GRAVITY);

console.log('altura máxima do pulo:', maxRise.toFixed(1) + 'px');
console.log('alcance horizontal no mesmo nível:', (MAX_SPEED * (2 * -JUMP_V / GRAVITY)).toFixed(1) + 'px');
console.log('');

// Distância horizontal máxima disponível ao chegar numa altura `dh` acima da
// origem, usando a raiz descendente (dá para passar do ápice e cair no alvo).
function reachAt(dh) {
  const disc = JUMP_V * JUMP_V - 2 * GRAVITY * dh;
  if (disc < 0) return -1;                       // altura inalcançável
  const t = (-JUMP_V + Math.sqrt(disc)) / GRAVITY;
  return MAX_SPEED * t;
}

let anyFail = false;
for (let i = 0; i < LEVELS.length; i++) {
  const L = LEVELS[i];
  const plats = L.plats.map(a => ({ x: a[0], y: a[1], w: a[2], h: a[3] }));
  const ground = plats.filter(q => q.y >= 470);
  const ledges = plats.filter(q => q.y < 470);

  // superfícies alcançáveis: começa pelo chão e expande
  const ok = new Set(ground);
  let changed = true;
  const why = new Map();
  while (changed) {
    changed = false;
    for (const t of ledges) {
      if (ok.has(t)) continue;
      for (const src of ok) {
        const dh = src.y - t.y;
        if (dh <= 0) continue;                   // alvo não está acima
        const dx = reachAt(dh);
        if (dx < 0) continue;
        // folga horizontal entre as bordas (0 se as faixas se sobrepõem)
        const gap = Math.max(0, Math.max(t.x - (src.x + src.w), src.x - (t.x + t.w)));
        if (gap <= dx - PW * .5) {
          ok.add(t); why.set(t, { dh, gap, dx });
          changed = true; break;
        }
      }
    }
  }

  console.log('--- ' + L.sub + ' · ' + L.name);
  for (const t of ledges) {
    const tag = ok.has(t) ? ' ok ' : 'FALHA';
    let detail = '';
    if (!ok.has(t)) {
      // melhor tentativa, para explicar o motivo
      let best = null;
      for (const src of plats) {
        const dh = src.y - t.y;
        if (dh <= 0) continue;
        const dx = reachAt(dh);
        const gap = Math.max(0, Math.max(t.x - (src.x + src.w), src.x - (t.x + t.w)));
        const score = dx < 0 ? -1e9 : dx - gap;
        if (!best || score > best.score) best = { dh, dx, gap, score, src };
      }
      detail = best.dx < 0
        ? '  altura ' + best.dh + 'px > máximo ' + maxRise.toFixed(0) + 'px'
        : '  precisa vencer ' + best.gap.toFixed(0) + 'px na horizontal, dispõe de ' + best.dx.toFixed(0) + 'px (subindo ' + best.dh + 'px)';
      anyFail = true;
    }
    console.log('  [' + tag + '] plataforma x=' + t.x + '..' + (t.x + t.w) + ' topo=' + t.y + detail);
  }
}
console.log('\n' + (anyFail ? 'HÁ PLATAFORMAS INALCANÇÁVEIS' : 'todas alcançáveis'));

// Saliência sobre buraco: se uma laje cruza a faixa vertical que o corpo do
// jogador percorre ao saltar o vão, ele bate por baixo, perde a subida e cai.
console.log('\n=== saliências bloqueando a travessia de buracos ===');
let blocked = 0;
for (let i = 0; i < LEVELS.length; i++) {
  const L = LEVELS[i];
  const ground = L.plats.filter(a => a[1] >= 470).map(a => ({x:a[0], w:a[2]})).sort((a,b) => a.x - b.x);
  const ledges = L.plats.filter(a => a[1] < 470).map(a => ({x:a[0], y:a[1], w:a[2], h:a[3]}));
  for (let k = 0; k + 1 < ground.length; k++) {
    const gapL = ground[k].x + ground[k].w, gapR = ground[k + 1].x;
    if (gapR <= gapL) continue;
    const arcL = gapL - PW - 40, arcR = gapR + 40;   // trecho em que ele está no ar
    const topAtGround = 470 - PH, topAtApex = topAtGround - maxRise;
    for (const q of ledges) {
      const overX = q.x < arcR && q.x + q.w > arcL;
      const overY = q.y < topAtGround && q.y + q.h > topAtApex;
      if (overX && overY) {
        blocked++;
        console.log('  [BLOQUEIA] ' + L.sub + ': vão ' + gapL + '..' + gapR +
                    ' tem laje x=' + q.x + '..' + (q.x + q.w) + ' base=' + (q.y + q.h) + ' no caminho');
      }
    }
  }
}
console.log(blocked ? '\n' + blocked + ' TRAVESSIA(S) BLOQUEADA(S)' : 'nenhuma travessia bloqueada');
