// Gera rlzoom.html: os sprites ampliados lado a lado, para conferir o pixel
// art de perto. No jogo o jogador tem 26x40px na tela — nessa escala é
// impossível julgar se o boné lê como boné ou como cabelo.
const fs = require('fs'), path = require('path');
const dir = __dirname;
const src = fs.readFileSync(path.join(dir, 'corte-seco-rl.html'), 'utf8').replace(/\r\n/g, '\n');

const anchor = 'cv.focus();\nrequestAnimationFrame(frame);';
if (!src.includes(anchor)) throw new Error('âncora não encontrada');

let html = src.replace(anchor,
  'globalThis.__RIG = {SPRITES, SPECS, PX, drawSword, ctx, S};\n' + anchor);

html += `
<script>
(() => {
  const start = () => {
    if (!globalThis.__RIG) return setTimeout(start, 10);
    const R = globalThis.__RIG;
    const cv = document.getElementById('cv');
    const g = cv.getContext('2d');
    document.getElementById('ov').classList.remove('on');

    // O loop do jogo continua rodando e repinta o canvas todo frame. Registrar
    // este desenho num rAF DEPOIS do dele faz a pintura do rig ficar por cima;
    // desenhar uma vez só resultava em tela preta.
    const draw = () => { paint(); requestAnimationFrame(draw); };

    function paint() {
    g.setTransform(1,0,0,1,0,0);
    g.fillStyle = '#2E2740';
    g.fillRect(0, 0, 960, 540);
    g.imageSmoothingEnabled = false;

    // grade 2 colunas x 3 linhas: em fila única o boss (28px de grade) sozinho
    // já estourava a largura do canvas e metade do elenco ficava fora da captura
    // os sprites já saem em 64x104px; qualquer aumento aqui estoura o canvas
    const Z = 1;
    const order = ['player','grunt','runner','brute','dummy','boss'];
    g.font = '600 13px Bahnschrift, system-ui, sans-serif';
    g.textAlign = 'left';

    order.forEach((name, i) => {
      const S2 = R.SPRITES[name];
      if (!S2) return;
      const col = i % 2, row = (i / 2) | 0;
      const ox = 30 + col * 470, oy = 40 + row * 150;

      g.fillStyle = '#E9E2D4';
      g.fillText(name.toUpperCase(), ox, oy);

      // o chefe tem grade 28x32 (56x64px reais); no mesmo Z dos outros ele
      // vaza o rodapé do canvas, então entra num aumento menor
      const z = Z;
      let fx = ox;
      for (let f = 0; f < 3; f++) {
        const img = S2.frames[f];
        const w = img.width * z, h = img.height * z;
        g.fillStyle = 'rgba(0,0,0,.28)';
        g.fillRect(fx - 4, oy + 12, w + 8, h + 8);
        g.drawImage(img, fx, oy + 16, w, h);
        fx += w + 12;
      }
    });

    // a espada ampliada, no mesmo aumento
    g.save();
    g.translate(160, 512);
    g.scale(2.6, 2.6);
    R.drawSword(0, 0, 0);
    g.restore();
    g.fillStyle = '#E9E2D4';
    g.fillText('ESPADA (2.6x)', 30, 516);

    g.fillStyle = '#8A93A3';
    g.font = '12px ui-monospace, monospace';
    g.fillText('tamanho real ·  jogador ' +
      (R.SPECS.player.gw * R.PX) + 'x' + (R.SPECS.player.gh * R.PX) + 'px  ·  grade ' +
      R.SPECS.player.gw + 'x' + R.SPECS.player.gh + ' a ' + R.PX + 'px', 400, 516);
    }

    requestAnimationFrame(draw);
  };
  start();
})();
</script>`;

fs.writeFileSync(path.join(dir, 'rlzoom.html'), html);
console.log('rlzoom.html gerado');
