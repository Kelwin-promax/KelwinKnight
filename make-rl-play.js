// Gera rlplay.html: o jogo com um bot embutido que dispara eventos de teclado
// REAIS na janela. Serve para provar que o loop roda de ponta a ponta num
// navegador — o harness em Node valida a lógica, mas roda com um stub de
// canvas e nunca desenha um pixel.
//
// Uso: node make-rl-play.js && chrome --headless --screenshot=... "rlplay.html?frames=N"
//
// A simulação é SÍNCRONA, com passo fixo de 1/60s, e não dirigida por
// requestAnimationFrame. Motivo: em Chrome headless o rAF dispara poucas vezes
// mesmo com --virtual-time-budget alto, e como o jogo trava dt em 1/30s, uma
// captura em "75s" mostrava 0.2s de jogo. Chamando frame() em laço o relógio
// vira nosso, e ?frames=N escolhe exatamente o momento capturado.
const fs = require('fs'), path = require('path');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'corte-seco-rl.html'), 'utf8').replace(/\r\n/g, '\n');

const anchor = 'cv.focus();\nrequestAnimationFrame(frame);';
if (!src.includes(anchor)) throw new Error('âncora não encontrada');

const SEED = 20260817;

let html = src.replace(anchor,
  'globalThis.__RIG = {startRun, loadFloor, S, p, TILE, FLOOR, ATK_RANGE, frame};\n' + anchor);

html += `
<script>
(() => {
  const start = () => {
    if (!globalThis.__RIG) return setTimeout(start, 10);
    const R = globalThis.__RIG;
    const { S, p, TILE, FLOOR, ATK_RANGE } = R;

    document.getElementById('ov').classList.remove('on');
    R.startRun(${SEED});

    // ---- teclado real: o bot passa pelo mesmo caminho de input do jogador
    const held = new Set();
    const press = k => {
      if (held.has(k)) return;
      held.add(k);
      dispatchEvent(new KeyboardEvent('keydown', { key: k }));
    };
    const releaseAll = () => {
      for (const k of [...held]) {
        held.delete(k);
        dispatchEvent(new KeyboardEvent('keyup', { key: k }));
      }
    };

    // ---- BFS na grade: sem isso o bot encalha na primeira quina de corredor
    function findPath(map, from, to) {
      if (from.tx === to.tx && from.ty === to.ty) return [[from.tx, from.ty]];
      const key = (x, y) => y * map.gw + x;
      const prev = new Map(), seen = new Set([key(from.tx, from.ty)]);
      let q = [[from.tx, from.ty]];
      while (q.length) {
        const next = [];
        for (const [x, y] of q) {
          for (const [nx, ny] of [[x+1,y],[x-1,y],[x,y+1],[x,y-1]]) {
            if (nx < 0 || ny < 0 || nx >= map.gw || ny >= map.gh) continue;
            if (map.grid[ny][nx] !== FLOOR) continue;
            const k = key(nx, ny);
            if (seen.has(k)) continue;
            seen.add(k); prev.set(k, [x, y]);
            if (nx === to.tx && ny === to.ty) {
              const out = [[nx, ny]];
              let cur = [x, y];
              while (!(cur[0] === from.tx && cur[1] === from.ty)) {
                out.push(cur);
                cur = prev.get(key(cur[0], cur[1]));
                if (!cur) return null;
              }
              out.push([from.tx, from.ty]);
              return out.reverse();
            }
            next.push([nx, ny]);
          }
        }
        q = next;
      }
      return null;
    }

    const tileOf = a => ({ tx: Math.floor(a.x / TILE), ty: Math.floor(a.y / TILE) });
    const steer = (dx, dy) => {
      if (dx > 6) press('d'); else if (dx < -6) press('a');
      if (dy > 6) press('s'); else if (dy < -6) press('w');
    };

    let path = null, repathT = 0, retreat = 0;

    function bot(dt) {
      releaseAll();

      // entre andares o jogo abre o overlay; o bot clica e continua
      if (S.mode === 'cleared' || S.mode === 'dead') {
        document.getElementById('ovBtn').click();
        return;
      }
      if (S.mode !== 'play') return;

      const boss = S.boss;
      let target = boss;
      if (!target) {
        let bd = Infinity;
        for (const e of S.enemies) {
          const d = Math.hypot(e.x - p.x, e.y - p.y);
          if (d < bd) { bd = d; target = e; }
        }
      }
      if (!target && S.exitOpen) {
        target = { x: S.map.exit.tx * TILE + TILE/2, y: S.map.exit.ty * TILE + TILE/2, r: 8, isExit: true };
      }
      if (!target) return;

      const dx = target.x - p.x, dy = target.y - p.y;
      const dist = Math.hypot(dx, dy);

      if (boss && (boss.state === 'telegraph' || boss.state === 'charge') && dist < 300 && p.dashCd <= 0) {
        const perp = boss.chargeAng + Math.PI / 2;
        steer(Math.cos(perp) * 100, Math.sin(perp) * 100);
        press('Shift');
        return;
      }
      if (!target.isExit && dist < ATK_RANGE + target.r - 6 && retreat <= 0) {
        steer(dx, dy); press('j'); retreat = .34; return;
      }
      if (retreat > 0) { retreat -= dt; steer(-dx, -dy); return; }

      repathT -= dt;
      if (repathT <= 0 || !path) {
        path = findPath(S.map, tileOf(p), tileOf(target));
        repathT = .2;
      }
      if (dist < TILE * 2.2 || !path || path.length < 2) { steer(dx, dy); return; }

      let wp = path[1];
      const wx = wp[0] * TILE + TILE/2, wy = wp[1] * TILE + TILE/2;
      if (Math.hypot(wx - p.x, wy - p.y) < 10 && path.length > 2) { path.shift(); wp = path[1]; }
      steer(wp[0] * TILE + TILE/2 - p.x, wp[1] * TILE + TILE/2 - p.y);
    }

    // ---- simulação síncrona de passo fixo
    // bot() decide, frame() atualiza e desenha. A última chamada deixa o canvas
    // no estado que a captura registra.
    const qs = new URLSearchParams(location.search);
    const TOTAL = parseInt(qs.get('frames') || '600', 10);
    const DT = 1 / 60;
    let clock = 0;

    // frame() se reagenda por requestAnimationFrame. Sem neutralizar isso, ao
    // fim do laço o rAF real volta com um timestamp muito ATRÁS do relógio
    // sintético, dt sai negativo e o jogo anda para trás: o flash de dano, que
    // decai por 'flash - dt*3', passa a CRESCER e satura a tela de vermelho.
    window.requestAnimationFrame = () => 0;

    for (let i = 0; i < TOTAL; i++) {
      bot(DT);
      clock += 1000 * DT;
      R.frame(clock);
    }
    releaseAll();

    // marcador no canto: prova que a imagem é uma run corrente, não pose estática
    const hud = document.createElement('div');
    hud.style.cssText = 'position:absolute;left:8px;bottom:8px;font:11px ui-monospace,monospace;color:#5AD1C8;z-index:9;pointer-events:none';
    document.querySelector('.stage').appendChild(hud);
    hud.textContent = 'BOT · frame ' + TOTAL + ' · andar ' + (S.depth + 1) + ' · ' +
      S.stats.time.toFixed(1) + 's · vida ' + Math.ceil(p.hp) +
      ' · abates ' + S.stats.kills + ' · modo ' + S.mode;
  };
  start();
})();
</script>`;

fs.writeFileSync(path.join(dir, 'rlplay.html'), html);
console.log('rlplay.html gerado (semente ' + SEED + ')');
