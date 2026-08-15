// Rig de zoom: roda o jogo normal e, por cima, amplia um recorte do canvas
// para avaliar a leitura dos personagens contra o cenário.
const fs = require('fs'), path = require('path');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8');
const anchor = 'buildSprites();\ncv.focus();';

const CROPS = [
  { name: 'zoomA', lvl: 3, px: 1250, sx: 360, sy: 330, sw: 340, sh: 191 },  // nível 4: vários inimigos
  { name: 'zoomB', lvl: 4, px: 700,  sx: 540, sy: 320, sw: 340, sh: 191 }   // chefe
];

for (const c of CROPS) {
  let html = src.replace(anchor, 'buildSprites();\nglobalThis.__RIG = {loadLevel, S, p, cv};\ncv.focus();');
  html += `
<script>
(() => {
  const go = () => {
    if (!globalThis.__RIG) return setTimeout(go, 10);
    const R = globalThis.__RIG;
    R.loadLevel(${c.lvl}, false);
    document.getElementById('ov').classList.remove('on');
    R.p.x = ${c.px};
    R.S.cam.x = Math.max(0, Math.min(${c.px} - 480, R.S.level.w - 960));
    R.S.camPrev = R.S.cam.x;
    R.S.hintTimer = 0;
    setInterval(() => { R.p.invuln = 0; R.p.hp = R.p.maxHp; }, 8);

    const z = document.createElement('canvas');
    z.width = 960; z.height = 540;
    z.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:auto;z-index:99;image-rendering:pixelated';
    document.body.appendChild(z);
    const zc = z.getContext('2d');
    const tick = () => {
      zc.imageSmoothingEnabled = false;
      zc.fillStyle = '#000'; zc.fillRect(0,0,960,540);
      zc.drawImage(R.cv, ${c.sx}, ${c.sy}, ${c.sw}, ${c.sh}, 0, 0, 960, 540);
      requestAnimationFrame(tick);
    };
    tick();
  };
  go();
})();
</script>`;
  fs.writeFileSync(path.join(dir, c.name + '.html'), html);
}
console.log('zoom rigs:', CROPS.map(c => c.name).join(', '));
