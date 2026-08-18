// Testes focados nos pontos que quebram calados neste jogo.
//
// No protótipo lateral os riscos eram inimigo caindo em buraco e latência do
// ataque. Sem gravidade o primeiro sumiu; no lugar dele entram os riscos
// próprios de um mundo em grade: ator atravessar parede em velocidade de dash
// e a IA perseguir através de pedra.
const { load, makeChecker } = require('./rl-stub');

const g = load();
const { D, press, releaseAll, step, DT } = g;
const { S, p, TILE, FLOOR, ATK_RANGE, ATK_ARC, ATK_DMG, DASH_SPEED, spawnEnemy, solidAt, lineOfSight,
        BLOCK_SPEED, BLOCK_REDUCE } = D;
const { check, state } = makeChecker();

const SEED = 4242;
const boot = (depth = 0) => { D.startRun(SEED); D.loadFloor(depth); releaseAll(); };

// Todos os cantos da pegada precisam estar em chão, não só o centro: um ator
// pode ter o centro em tile livre e metade do corpo dentro da parede.
function footprintClear(a) {
  for (const [ox, oy] of [[-1,-1],[1,-1],[-1,1],[1,1]]) {
    const x = a.x + ox * (a.r - .5), y = a.y + oy * (a.r - .5);
    if (solidAt(Math.floor(x / TILE), Math.floor(y / TILE))) return false;
  }
  return true;
}

// ------------------------------------------------------- latência do ataque
console.log('=== hitbox ativa no 1º frame após J ===');
{
  boot(0);
  S.enemies.length = 0;
  const e = spawnEnemy('grunt', p.x + 30, p.y, 1);
  S.enemies.push(e);
  const hp0 = e.hp;

  press('d');            // mira para a direita, onde o inimigo está
  step();
  const hpAfterMove = e.hp;
  press('j');
  step();

  check('inimigo levou dano no mesmo frame do input', e.hp < hpAfterMove,
    `vida ${hp0} -> ${e.hp}`);
  check('o dano aplicado é ATK_DMG', hpAfterMove - e.hp === ATK_DMG,
    `${hpAfterMove - e.hp} de dano`);
}

console.log('\n=== cadência entre golpes ===');
{
  boot(0);
  S.enemies.length = 0;
  // saco de pancada imortal: mede cadência sem o alvo morrer no meio
  const e = spawnEnemy('grunt', p.x + 30, p.y, 1);
  e.hp = 1e9; e.maxHp = 1e9;
  S.enemies.push(e);

  const hits = [];
  let prevHp = e.hp;
  for (let f = 0; f < 60; f++) {          // 1 segundo
    releaseAll();
    press('d');
    press('j');
    step();
    if (e.hp < prevHp) { hits.push(f); prevHp = e.hp; }
    e.stun = 0; e.vx = 0; e.vy = 0;       // trava no lugar
    e.x = p.x + 30; e.y = p.y;
  }
  check('mais de um golpe em 1 segundo', hits.length >= 3, `${hits.length} acertos`);
  if (hits.length >= 2) {
    const gaps = hits.slice(1).map((h, i) => (h - hits[i]) * DT * 1000);
    const avg = gaps.reduce((a, b) => a + b, 0) / gaps.length;
    check('cadência entre golpes ~310ms', avg > 250 && avg < 380, `${avg.toFixed(0)}ms`);
  }
}

console.log('\n=== o arco só acerta na frente ===');
{
  boot(0);
  S.enemies.length = 0;
  const front = spawnEnemy('grunt', p.x + 34, p.y, 1);
  const back = spawnEnemy('grunt', p.x - 34, p.y, 1);
  S.enemies.push(front, back);
  press('d');
  step();
  press('j');
  step();
  check('inimigo à frente da mira leva dano', front.hp < front.maxHp, `${front.hp}/${front.maxHp}`);
  check('inimigo atrás da mira não leva dano', back.hp === back.maxHp, `${back.hp}/${back.maxHp}`);
}

console.log('\n=== alcance do golpe ===');
{
  boot(0);
  S.enemies.length = 0;
  const far = spawnEnemy('grunt', p.x + ATK_RANGE + 60, p.y, 1);
  S.enemies.push(far);
  press('d');
  step();
  press('j');
  step();
  check('inimigo fora de alcance não leva dano', far.hp === far.maxHp,
    `a ${ATK_RANGE + 60}px, alcance ${ATK_RANGE}px`);
}

// ------------------------------------------------------- colisão com parede
console.log('\n=== ninguém atravessa parede ===');
{
  // O dash é o caso perigoso: DASH_SPEED px/s com dt travado em 1/30 dá o
  // maior passo por frame do jogo. Se esse passo passar de TILE, o ator
  // atravessa a parede inteira num frame e o teste pega.
  const maxStep = DASH_SPEED / 30;
  check('o maior passo por frame é menor que um tile', maxStep < TILE,
    `${maxStep.toFixed(1)}px por frame, tile ${TILE}px`);

  boot(0);
  let breaches = 0, worst = null;
  const dirs = [['d'], ['a'], ['w'], ['s'], ['d','w'], ['d','s'], ['a','w'], ['a','s']];
  for (let round = 0; round < dirs.length; round++) {
    for (let f = 0; f < 260; f++) {
      releaseAll();
      for (const k of dirs[round]) press(k);
      if (f % 55 === 0) press('shift');     // dash contra a parede
      step();
      if (!footprintClear(p)) {
        breaches++;
        if (!worst) worst = `dir=${dirs[round].join('+')} frame=${f} pos=(${p.x.toFixed(0)},${p.y.toFixed(0)})`;
      }
    }
  }
  check('jogador nunca entrou em tile de parede, nem em dash',
    breaches === 0, breaches ? `${breaches} violações, 1ª: ${worst}` : '2080 frames contra parede');
}

console.log('\n=== inimigos também respeitam a parede ===');
{
  boot(3);                                  // Ossário: mapa maior, 10 inimigos
  let breaches = 0;
  for (let f = 0; f < 900; f++) {
    releaseAll();
    // o jogador foge em círculo, puxando o bando por corredores
    press(f % 120 < 60 ? 'd' : 'a');
    press(f % 240 < 120 ? 's' : 'w');
    step();
    for (const e of S.enemies) if (!footprintClear(e)) breaches++;
  }
  check('nenhum inimigo entrou em tile de parede', breaches === 0,
    breaches ? `${breaches} violações` : `${S.enemies.length} inimigos por 900 frames`);
}

// ------------------------------------------------------- linha de visão
console.log('\n=== a IA não persegue através de pedra ===');
{
  boot(3);
  const map = S.map;

  // procura dois tiles de chão perto um do outro com parede na reta entre eles
  let blocked = null, clear = null;
  for (let ty = 1; ty < map.gh - 1 && (!blocked || !clear); ty++) {
    for (let tx = 1; tx < map.gw - 1 && (!blocked || !clear); tx++) {
      if (map.grid[ty][tx] !== FLOOR) continue;
      const ax = tx * TILE + TILE/2, ay = ty * TILE + TILE/2;
      for (let oy = -5; oy <= 5 && (!blocked || !clear); oy++) {
        for (let ox = -5; ox <= 5; ox++) {
          const nx = tx + ox, ny = ty + oy;
          if (nx < 1 || ny < 1 || nx >= map.gw - 1 || ny >= map.gh - 1) continue;
          if (map.grid[ny][nx] !== FLOOR) continue;
          const bx = nx * TILE + TILE/2, by = ny * TILE + TILE/2;
          const d = Math.hypot(bx - ax, by - ay);
          if (d < TILE * 2 || d > 300) continue;
          const los = lineOfSight(ax, ay, bx, by);
          if (!los && !blocked) blocked = [ax, ay, bx, by, d];
          if (los && !clear) clear = [ax, ay, bx, by, d];
          if (blocked && clear) break;
        }
      }
    }
  }

  check('o mapa tem par de pontos com parede no meio (setup do teste)', !!blocked,
    blocked ? `dist ${blocked[4].toFixed(0)}px` : 'não encontrado');
  check('o mapa tem par de pontos com visão livre (controle)', !!clear,
    clear ? `dist ${clear[4].toFixed(0)}px` : 'não encontrado');

  if (blocked) {
    S.enemies.length = 0;
    p.x = blocked[0]; p.y = blocked[1]; p.vx = 0; p.vy = 0;
    const e = spawnEnemy('runner', blocked[2], blocked[3], 1);   // aggro 560 > dist
    S.enemies.push(e);
    for (let f = 0; f < 30; f++) { releaseAll(); step(); }
    check('inimigo atrás de parede não fica alerta', e.alert === false,
      `dist ${blocked[4].toFixed(0)}px, aggro ${e.aggro}`);
  }

  if (clear) {
    boot(3);
    S.enemies.length = 0;
    p.x = clear[0]; p.y = clear[1]; p.vx = 0; p.vy = 0;
    const e = spawnEnemy('runner', clear[2], clear[3], 1);
    S.enemies.push(e);
    for (let f = 0; f < 30; f++) { releaseAll(); step(); }
    check('inimigo com visão livre fica alerta (controle)', e.alert === true,
      `dist ${clear[4].toFixed(0)}px`);
  }
}

// ------------------------------------------------------- dash
console.log('\n=== dash concede invencibilidade ===');
{
  boot(0);
  S.enemies.length = 0;
  p.invuln = 0;
  const e = spawnEnemy('grunt', p.x + 20, p.y, 1);
  S.enemies.push(e);

  const hp0 = p.hp;
  press('shift'); press('a');
  step();
  check('dash começa com invencibilidade ativa', p.invuln > 0, `invuln=${p.invuln.toFixed(2)}s`);
  for (let f = 0; f < 8; f++) { releaseAll(); press('a'); step(); e.x = p.x + 18; e.y = p.y; e.touchCd = 0; }
  check('jogador não levou dano durante o dash', p.hp === hp0, `${hp0} -> ${p.hp}`);

  // controle: sem dash e sem i-frames, o mesmo encosto machuca
  boot(0);
  S.enemies.length = 0;
  p.invuln = 0;
  const e2 = spawnEnemy('grunt', p.x + 20, p.y, 1);
  S.enemies.push(e2);
  const hp1 = p.hp;
  for (let f = 0; f < 8; f++) { releaseAll(); step(); e2.x = p.x + 18; e2.y = p.y; }
  check('sem dash o mesmo encosto machuca (controle)', p.hp < hp1, `${hp1} -> ${p.hp}`);
}

// ------------------------------------------------------- defesa
console.log('\n=== a guarda corta o dano que vem de frente ===');
{
  // Encosto pela DIREITA com a mira para a direita: o golpe entra no arco.
  boot(0);
  S.enemies.length = 0;
  p.invuln = 0;
  const e = spawnEnemy('grunt', p.x + 20, p.y, 1);
  S.enemies.push(e);
  const hp0 = p.hp;
  for (let f = 0; f < 6; f++) {
    releaseAll(); press('k');            // segura a guarda
    p.aim = 0;                            // mirando para a direita
    step();
    e.x = p.x + 18; e.y = p.y; e.touchCd = 0;
  }
  const dmgDefendido = hp0 - p.hp;

  // Controle: mesmo encosto, sem guarda.
  boot(0);
  S.enemies.length = 0;
  p.invuln = 0;
  const e2 = spawnEnemy('grunt', p.x + 20, p.y, 1);
  S.enemies.push(e2);
  const hp1 = p.hp;
  for (let f = 0; f < 6; f++) {
    releaseAll();
    p.aim = 0;
    step();
    e2.x = p.x + 18; e2.y = p.y; e2.touchCd = 0;
  }
  const dmgLivre = hp1 - p.hp;

  check('sem guarda o encosto machuca (controle)', dmgLivre > 0, dmgLivre + ' de dano');
  check('de guarda o mesmo encosto machuca menos', dmgDefendido < dmgLivre,
    dmgLivre + ' -> ' + dmgDefendido + ' de dano');
  check('a reducao bate com BLOCK_REDUCE', dmgDefendido === Math.max(1, Math.round(dmgLivre * (1 - BLOCK_REDUCE))),
    'esperado ' + Math.max(1, Math.round(dmgLivre * (1 - BLOCK_REDUCE))) + ', veio ' + dmgDefendido);
}

console.log('\n=== a guarda nao protege as costas ===');
{
  // Encosto pela DIREITA, mas mirando para a ESQUERDA: fora do arco.
  boot(0);
  S.enemies.length = 0;
  p.invuln = 0;
  const e = spawnEnemy('grunt', p.x + 20, p.y, 1);
  S.enemies.push(e);
  const hp0 = p.hp;
  for (let f = 0; f < 6; f++) {
    releaseAll(); press('k');
    p.aim = Math.PI;                      // de costas para o inimigo
    step();
    e.x = p.x + 18; e.y = p.y; e.touchCd = 0;
  }
  const dmgCostas = hp0 - p.hp;

  boot(0);
  S.enemies.length = 0;
  p.invuln = 0;
  const e2 = spawnEnemy('grunt', p.x + 20, p.y, 1);
  S.enemies.push(e2);
  const hp1 = p.hp;
  for (let f = 0; f < 6; f++) {
    releaseAll();
    p.aim = Math.PI;
    step();
    e2.x = p.x + 18; e2.y = p.y; e2.touchCd = 0;
  }
  const dmgLivre = hp1 - p.hp;

  check('golpe nas costas passa inteiro pela guarda', dmgCostas === dmgLivre,
    'de costas ' + dmgCostas + ', sem guarda ' + dmgLivre);
}

console.log('\n=== a guarda custa mobilidade e acao ===');
{
  boot(0);
  S.enemies.length = 0;
  for (let f = 0; f < 30; f++) { releaseAll(); press('k'); press('d'); step(); }
  const vGuarda = Math.hypot(p.vx, p.vy);

  boot(0);
  S.enemies.length = 0;
  for (let f = 0; f < 30; f++) { releaseAll(); press('d'); step(); }
  const vLivre = Math.hypot(p.vx, p.vy);

  check('de guarda anda mais devagar', vGuarda < vLivre,
    vLivre.toFixed(0) + ' -> ' + vGuarda.toFixed(0) + ' px/s');
  check('a velocidade de guarda bate com BLOCK_SPEED',
    Math.abs(vGuarda / vLivre - BLOCK_SPEED) < .06,
    'razao ' + (vGuarda / vLivre).toFixed(2) + ', esperado ' + BLOCK_SPEED);

  // nao ataca de guarda
  boot(0);
  S.enemies.length = 0;
  const e = spawnEnemy('grunt', p.x + 30, p.y, 1);
  e.hp = 1e9; e.maxHp = 1e9;
  S.enemies.push(e);
  const hpAlvo = e.hp;
  for (let f = 0; f < 20; f++) { releaseAll(); press('k'); press('j'); p.aim = 0; step(); }
  check('segurando a guarda o ataque nao sai', e.hp === hpAlvo, 'alvo intacto');

  // nao dasha de guarda
  boot(0);
  S.enemies.length = 0;
  releaseAll(); press('k'); press('shift'); press('d');
  step();
  check('segurando a guarda o dash nao sai', p.dash <= 0, 'dash=' + p.dash.toFixed(2));
}

console.log(state.failures ? `\n${state.failures} FALHA(S)` : '\nTODOS OS TESTES PASSARAM');
process.exit(state.failures ? 1 : 0);
