// Gera um HTML "rig" por andar (carrega o andar direto, posiciona o jogador e
// roda alguns frames) para o Chrome headless tirar screenshot e eu conferir a
// masmorra de verdade.
//
// Lê com normalização de CRLF: em checkout Windows com core.autocrlf=true o
// arquivo chega com \r\n e a âncora escrita com \n literal não casaria.
const fs = require('fs'), path = require('path');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'corte-seco-rl.html'), 'utf8').replace(/\r\n/g, '\n');

const anchor = 'cv.focus();\nrequestAnimationFrame(frame);';
if (!src.includes(anchor)) throw new Error('âncora não encontrada');

const SEED = 20260817;

for (let depth = 0; depth < 5; depth++) {
  let html = src.replace(anchor, 'globalThis.__RIG = {startRun, loadFloor, S, p, TILE};\n' + anchor);
  html += `
<script>
(() => {
  const start = () => {
    if (!globalThis.__RIG) return setTimeout(start, 10);
    const R = globalThis.__RIG;
    R.startRun(${SEED});
    R.loadFloor(${depth});
    document.getElementById('ov').classList.remove('on');
    R.S.hintTimer = 0;

    // No andar do chefe vale enquadrar o confronto; nos outros, o jogador
    // perto do inimigo mais próximo, senão a captura pega corredor vazio.
    if (R.S.boss) {
      R.p.x = R.S.boss.x - 150;
      R.p.y = R.S.boss.y;
      R.S.boss.state = 'telegraph';
      R.S.boss.t = 999;
      R.S.boss.chargeAng = Math.atan2(R.p.y - R.S.boss.y, R.p.x - R.S.boss.x);
    } else if (R.S.enemies.length) {
      const e = R.S.enemies[0];
      // 70px de folga empilhava os corpos: o sprite tem 64px de largura, então
      // o jogador sumia atrás do inimigo. Precisa de mais que uma largura.
      R.p.x = e.x - 150;
      R.p.y = e.y + 70;
      for (const en of R.S.enemies) en.alert = true;
    }
    R.S.cam.x = Math.max(0, Math.min(R.p.x - 480, R.S.map.gw * R.TILE - 960));
    R.S.cam.y = Math.max(0, Math.min(R.p.y - 270, R.S.map.gh * R.TILE - 540));

    // mantém o jogador vivo e sem piscar de invencibilidade, senão ele pode
    // sumir justo no frame do screenshot
    setInterval(() => { R.p.invuln = 0; R.p.hp = R.p.maxHp; }, 8);
  };
  start();
})();
</script>`;
  fs.writeFileSync(path.join(dir, `rlshot${depth + 1}.html`), html);
}
console.log('rigs gerados: 5');
