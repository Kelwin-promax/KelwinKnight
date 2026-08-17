// Harness headless: um bot desce os cinco andares e mede a curva de
// dificuldade. Equivalente ao harness.js do protótipo lateral, reescrito para
// o mundo top-down.
//
// A diferença que importa: aqui o bot precisa de PATHFINDING. No jogo lateral
// dava para andar reto até o inimigo; numa masmorra com corredores em L, andar
// reto encosta na parede e trava. O bot usa BFS na grade e segue waypoints.
const { load, makeChecker, findPath } = require('./rl-stub');

const g = load();
const { D, press, releaseAll, step, DT } = g;
const { S, p, FLOORS, TILE, FLOOR, ATK_RANGE } = D;
const { check, state } = makeChecker();

const SEED = 20260817;          // semente fixa: a run do teste é reproduzível
const FRAME_BUDGET = 70 * 60;   // 70s por andar antes de declarar travamento
const MAX_RUNS = 8;

// ------------------------------------------------------------------ bot
let path = null, repathT = 0, retreat = 0, lastTargetKey = '';

const tileOf = a => ({ tx: Math.floor(a.x / TILE), ty: Math.floor(a.y / TILE) });

function nearestEnemy() {
  let best = null, bd = Infinity;
  for (const e of S.enemies) {
    const d = Math.hypot(e.x - p.x, e.y - p.y);
    if (d < bd) { bd = d; best = e; }
  }
  return best;
}

// Converte um vetor de direção em teclas. Zona morta de 6px evita o bot
// tremer entre 'a' e 'd' quando está praticamente alinhado.
// Zona morta proporcional ao tile: com TILE=64 uma zona de 6px fazia o bot
// tremer entre 'a' e 'd' em vez de assentar no waypoint.
const DEAD = TILE * .15;
function steer(dx, dy) {
  if (dx > DEAD) press('d'); else if (dx < -DEAD) press('a');
  if (dy > DEAD) press('s'); else if (dy < -DEAD) press('w');
}

function bot(dt) {
  releaseAll();
  if (S.mode !== 'play') return;

  const boss = S.boss;
  const target = boss || nearestEnemy() ||
    (S.exitOpen ? { x: S.map.exit.tx * TILE + TILE/2, y: S.map.exit.ty * TILE + TILE/2, r: 8, isExit: true } : null);
  if (!target) return;

  const dx = target.x - p.x, dy = target.y - p.y;
  const dist = Math.hypot(dx, dy);

  // esquiva da investida do chefe: dash perpendicular ao rumo travado
  if (boss && (boss.state === 'telegraph' || boss.state === 'charge') && dist < 300 && p.dashCd <= 0) {
    const perp = boss.chargeAng + Math.PI / 2;
    steer(Math.cos(perp) * 100, Math.sin(perp) * 100);
    press('shift');
    return;
  }

  // no alcance: mira andando na direção do alvo (a mira segue o movimento
  // quando não há mouse) e golpeia
  if (!target.isExit && dist < ATK_RANGE + target.r - 6 && retreat <= 0) {
    steer(dx, dy);
    press('j');
    retreat = .34;
    return;
  }
  if (retreat > 0) {
    retreat -= dt;
    steer(-dx, -dy);
    return;
  }

  // caminho até o alvo, recalculado a cada 200ms
  repathT -= dt;
  const key = target.isExit ? 'exit' : `${Math.round(target.x)},${Math.round(target.y)}`;
  if (repathT <= 0 || !path || key.slice(0, 4) !== lastTargetKey.slice(0, 4)) {
    path = findPath(S.map, tileOf(p), tileOf(target), FLOOR);
    repathT = .2;
    lastTargetKey = key;
  }

  // linha de visão livre e perto: vai direto, sem waypoint
  if (dist < TILE * 2.2 || !path || path.length < 2) { steer(dx, dy); return; }

  // pula waypoints já ultrapassados
  let wp = path[1];
  const wx = wp[0] * TILE + TILE/2, wy = wp[1] * TILE + TILE/2;
  if (Math.hypot(wx - p.x, wy - p.y) < TILE * .25 && path.length > 2) {
    path.shift();
    wp = path[1];
  }
  steer(wp[0] * TILE + TILE/2 - p.x, wp[1] * TILE + TILE/2 - p.y);
}

// ------------------------------------------------------------------ smoke
console.log('=== smoke ===');
check('overlay de título aberto', g.overlayOpen(), g.title());
check('título correto', g.title() === 'Corte Seco', g.title());
g.clickPrimary();
check('começar fecha o overlay', !g.overlayOpen());

// o botão sorteia semente; refixa para a run do teste ser reproduzível
D.startRun(SEED);
check('run começa no andar 1', S.depth === 0, S.floor.name);
check('masmorra carregada', !!S.map && S.map.grid.length > 0, `${S.map.gw}x${S.map.gh} tiles`);
check('jogador nasce em chão',
  S.map.grid[Math.floor(p.y / TILE)][Math.floor(p.x / TILE)] === FLOOR);
check('escada começa fechada', S.exitOpen === false);

// ------------------------------------------------------------------ run
console.log('\n=== playthrough (bot) ===');

const curve = [];
let deaths = 0, completed = false, stuck = null;

for (let run = 1; run <= MAX_RUNS && !completed; run++) {
  D.startRun(SEED + run - 1);
  curve.length = 0;
  let died = false;

  for (let depth = 0; depth < FLOORS.length && !died; depth++) {
    const startDmg = S.stats.dmg, startTime = S.stats.time;
    let frames = 0;

    while (S.mode === 'play' && frames < FRAME_BUDGET) {
      bot(DT);
      if (!step()) throw new Error('o loop parou de agendar frames');
      frames++;
    }

    if (S.mode === 'play') {
      stuck = `andar ${depth + 1} (run ${run}): bot não terminou em ${(FRAME_BUDGET / 60).toFixed(0)}s`;
      break;
    }
    if (S.mode === 'dead') {
      deaths++;
      died = true;
      g.clickPrimary();     // permadeath: volta ao andar 1 com nova semente
      break;
    }

    curve.push({
      depth: depth + 1,
      name: FLOORS[depth].name,
      time: S.stats.time - startTime,
      dmg: S.stats.dmg - startDmg,
      frames
    });

    if (depth === FLOORS.length - 1) { completed = true; break; }
    g.clickPrimary();       // desce a escada
  }
  if (stuck) break;
}

check('bot não travou em nenhum andar', stuck === null, stuck || 'nenhum travamento');
check('bot completou os cinco andares numa run só', completed,
  completed ? `com ${deaths} morte(s) em runs anteriores` : `desistiu após ${MAX_RUNS} runs`);

if (curve.length) {
  console.log('\n=== curva medida (run completa do bot) ===');
  console.log(' andar | nome            | tempo   | dano sofrido');
  for (const r of curve) {
    console.log(`   ${r.depth}   | ${r.name.padEnd(15)} | ${r.time.toFixed(1).padStart(5)}s  | ${r.dmg}`);
  }

  const dmgs = curve.map(r => r.dmg);
  check('andar 1 é o de menor dano', dmgs[0] === Math.min(...dmgs), dmgs.join(' → '));
  check('o chefe cobra mais caro que o andar 1', dmgs[dmgs.length - 1] > dmgs[0],
    `andar 1 = ${dmgs[0]}, chefe = ${dmgs[dmgs.length - 1]}`);
  check('nenhum andar ficou trivial demais (0 inimigos mortos)',
    S.stats.kills > 0, `${S.stats.kills} abates na run`);
}

// ------------------------------------------------------------------ pausa
console.log('\n=== pausa e permadeath ===');
D.startRun(SEED);
g.keyDown('p');
check('P pausa', S.mode === 'paused', S.mode);
g.keyUp('p');
g.keyDown('p');
check('P despausa', S.mode === 'play', S.mode);
g.keyUp('p');

// permadeath: matar o jogador tem de encerrar a run, não o andar
D.startRun(SEED);
D.loadFloor(2);
const depthAtDeath = S.depth;
p.hp = 1;
p.invuln = 0;
S.enemies.length = 0;
// dano direto o bastante para zerar a vida
const before = S.stats.run;
p.hp = 0.5;
p.invuln = 0;
S.enemies.push(D.spawnEnemy('grunt', p.x + 10, p.y, 3));
for (let i = 0; i < 240 && S.mode === 'play'; i++) { releaseAll(); step(); }
check('encostar em inimigo com 0.5 de vida mata', S.mode === 'dead', `modo=${S.mode}, hp=${p.hp}`);
check('a morte oferece nova run, não retomar o andar',
  g.title().includes('Morto no andar ' + (depthAtDeath + 1)), g.title());
g.clickPrimary();
check('nova run recomeça do andar 1', S.depth === 0, `andar ${S.depth + 1}`);
check('nova run restaura a vida cheia', p.hp === p.maxHp, `${p.hp}/${p.maxHp}`);
check('contador de run avançou', S.stats.run > before, `${before} → ${S.stats.run}`);

console.log(state.failures ? `\n${state.failures} FALHA(S)` : '\nTODOS OS TESTES PASSARAM');
process.exit(state.failures ? 1 : 0);
