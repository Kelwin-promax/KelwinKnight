// Prova empírica: simula o jogador correndo e pulando em cada plataforma
// suspensa, usando a física real, e confirma que ele pousa nela.
const fs = require('fs'), path = require('path'), vm = require('vm');
const dir = __dirname;
let code = /<script>([\s\S]*)<\/script>/.exec(fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8'))[1];
code = code.replace('buildSprites();\ncv.focus();',
  'globalThis.__D = {loadLevel, S, p, LEVELS};\nbuildSprites();\ncv.focus();');

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
const clearKeys = () => ['a','d',' ','shift','j'].forEach(ku);

// L.plats guarda arrays crus [x,y,w,h] — ler .y aqui devolvia undefined e
// fazia todas as tentativas serem puladas silenciosamente.
const groundYAt = (plats, x) => {
  let best = null;
  for (const q of plats) {
    const [qx, qy, qw] = q;
    if (qy >= 470 && x > qx && x < qx + qw) if (best == null || qy < best) best = qy;
  }
  return best;
};

let fails = 0, total = 0;
for (let i = 0; i < D.LEVELS.length; i++) {
  const L = D.LEVELS[i];
  const ledges = L.plats.filter(a => a[1] < 470).map(a => ({x:a[0], y:a[1], w:a[2]}));
  console.log('--- ' + L.sub + ' · ' + L.name);

  for (const t of ledges) {
    total++;
    let landed = null;

    // Varre origens dos dois lados e o instante do pulo. `dist` é a folga até
    // a borda no momento de saltar — pular tarde faz bater embaixo da laje.
    // A origem é presa ao segmento de chão em teste: partir de uma distância
    // fixa atravessaria buracos e reprovaria plataformas perfeitamente boas.
    const segs = L.plats.filter(a => a[1] >= 470).map(a => ({x:a[0], y:a[1], w:a[2]}));
    outer:
    for (const g of segs) {
      for (const side of ['esq', 'dir']) {
        for (const runway of [340, 260, 180, 120, 60]) {
          for (const dist of [10, 30, 50, 70, 90, 120]) {
          D.loadLevel(i, false);
          D.S.enemies.length = 0; D.S.boss = null;      // sem interferência
          const raw = side === 'esq' ? t.x - runway : t.x + t.w + runway;
          const startX = Math.max(g.x + 4, Math.min(g.x + g.w - 30, raw));
          const gy = groundYAt(L.plats, startX + 13);
          if (gy == null || gy !== g.y) continue;        // origem fora do segmento
          D.p.x = startX; D.p.y = gy - D.p.h;
          D.p.vx = 0; D.p.vy = 0; D.p.invuln = 999;
          clearKeys();

          const dirKey = side === 'esq' ? 'd' : 'a';
          const gapNow = () => side === 'esq' ? t.x - (D.p.x + D.p.w) : D.p.x - (t.x + t.w);
          kd(dirKey);
          let ok = false;
          for (let f = 0; f < 200 && gapNow() > dist; f++) { step(); ok = true; }
          if (gapNow() > dist) continue;                 // nunca chegou perto
          kd(' ');                                       // pula e SEGURA o botão
          for (let f = 0; f < 120; f++) {
            step();
            const onTop = D.p.onGround
              && Math.abs((D.p.y + D.p.h) - t.y) < 2.5
              && D.p.x + D.p.w > t.x && D.p.x < t.x + t.w;
            if (onTop) { landed = { side, runway, dist }; break outer; }
          }
          }
        }
      }
    }

    if (landed) {
      console.log('  [ ok ] topo=' + t.y + ' x=' + t.x + '..' + (t.x + t.w) +
                  '  (pela ' + landed.side + ', salto a ' + landed.dist + 'px da borda)');
    } else {
      console.log('  [FALHA] topo=' + t.y + ' x=' + t.x + '..' + (t.x + t.w) + '  nenhuma origem funcionou');
      fails++;
    }
  }
}
console.log('\n' + (fails ? fails + ' de ' + total + ' PLATAFORMAS INALCANÇÁVEIS'
                          : 'todas as ' + total + ' plataformas alcançadas na simulação'));
process.exit(fails ? 1 : 0);
