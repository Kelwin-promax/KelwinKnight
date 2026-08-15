// Gera um HTML "rig" por nível (carrega o nível direto e roda alguns frames)
// para o Chrome headless tirar screenshot e eu conferir o cenário de verdade.
const fs = require('fs'), path = require('path');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8');

const anchor = 'cv.focus();\nrequestAnimationFrame(frame);';
if (!src.includes(anchor)) throw new Error('âncora não encontrada');

// nível -> posição do jogador, para enquadrar um trecho representativo
const SHOTS = [
  { lvl: 0, x: 620 },
  { lvl: 1, x: 900 },
  { lvl: 2, x: 1150 },
  { lvl: 3, x: 1250 },
  { lvl: 4, x: 700 }
];

for (const s of SHOTS) {
  let html = src.replace(anchor, 'globalThis.__RIG = {loadLevel, S, p};\n' + anchor);
  html += `
<script>
(() => {
  const start = () => {
    if (!globalThis.__RIG) return setTimeout(start, 10);
    const R = globalThis.__RIG;
    R.loadLevel(${s.lvl}, false);
    document.getElementById('ov').classList.remove('on');
    R.p.x = ${s.x};
    R.S.cam.x = Math.max(0, Math.min(${s.x} - 480, R.S.level.w - 960));
    R.S.camPrev = R.S.cam.x;
    R.S.hintTimer = 0;
    // mantém o jogador vivo e sem piscar de invencibilidade, senão ele
    // pode sumir justo no frame do screenshot
    setInterval(() => { R.p.invuln = 0; R.p.hp = R.p.maxHp; }, 8);
  };
  start();
})();
</script>`;
  fs.writeFileSync(path.join(dir, `shot${s.lvl + 1}.html`), html);
}
console.log('rigs gerados:', SHOTS.length);
