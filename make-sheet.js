// Rig que desenha todos os sprites ampliados, para inspecionar o pixel art.
const fs = require('fs'), path = require('path');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'corte-seco.html'), 'utf8');
const anchor = 'buildSprites();\ncv.focus();';
if (!src.includes(anchor)) throw new Error('Ã¢ncora nÃ£o encontrada');

let html = src.replace(anchor, 'buildSprites();\nglobalThis.__RIG = {SPRITES, S, ctx, cv, drawSword};\ncv.focus();');
html += `
<script>
(() => {
  const go = () => {
    if (!globalThis.__RIG) return setTimeout(go, 10);
    const { SPRITES, S, ctx, cv } = globalThis.__RIG;
    document.getElementById('ov').classList.remove('on');
    S.mode = 'sheet';                       // impede o loop do jogo de redesenhar
    const Z = 3;
    const paint = () => {
      ctx.setTransform(1,0,0,1,0,0);
      ctx.imageSmoothingEnabled = false;
      ctx.fillStyle = '#15121C'; ctx.fillRect(0,0,960,540);
      const order = ['player','dummy','grunt','runner','brute','boss'];
      let x = 24, y = 40;
      for (const k of order) {
        const S2 = SPRITES[k], img0 = S2.frames[0];
        const blockW = img0.width * Z * 3 + 24 + 30;
        if (x + blockW > 950) { x = 24; y += 150; }
        ctx.fillStyle = '#8A93A3';
        ctx.font = '12px ui-monospace, monospace';
        ctx.fillText(k, x, y - 8);
        for (let f = 0; f < 3; f++) {
          const img = S2.frames[f];
          ctx.drawImage(img, x + f * (img.width * Z + 10), y, img.width * Z, img.height * Z);
        }
        x += blockW;
      }
      requestAnimationFrame(paint);
    };
    paint();
  };
  go();
})();
</script>`;
fs.writeFileSync(path.join(dir, 'sheet.html'), html);
console.log('sheet.html gerado');

