// Validação da geração procedural — substitui reach.js e jumptest.js, que
// mediam alcance de pulo e não significam mais nada sem gravidade.
//
// O risco de um roguelike não é uma plataforma alta demais: é uma semente
// gerar sala isolada, inimigo dentro de parede ou escada inalcançável, e o
// jogador ficar preso num andar que não dá para limpar. Então o teste varre
// MUITAS sementes e afirma as invariantes em todas.
const { load, makeChecker } = require('./rl-stub');

const g = load();
const { D } = g;
const { genDungeon, reachable, FLOORS, TYPES, TILE, FLOOR } = D;
const { check, state } = makeChecker();

const SEEDS = 400;

// ---------------------------------------------------------------- invariante
// O corredor mais estreito tem 1 tile. A maior pegada é a do brute (r=19),
// que ocupa 2*19=38px. Se TILE cair abaixo disso, o brute entala no corredor
// e o andar fica impossível — sem barulho nenhum, ele só para de perseguir.
console.log('=== folga da pegada no corredor ===');
const maxR = Math.max(...Object.values(TYPES).map(t => t.r));
check('a maior pegada de inimigo cabe num corredor de 1 tile',
  maxR * 2 <= TILE, `maior r=${maxR} → ${maxR * 2}px, tile=${TILE}px`);

// ---------------------------------------------------------------- determinismo
console.log('\n=== determinismo ===');
{
  const a = genDungeon(12345, 2);
  const b = genDungeon(12345, 2);
  const same = JSON.stringify(a.grid) === JSON.stringify(b.grid) &&
               a.spawn.tx === b.spawn.tx && a.spawn.ty === b.spawn.ty &&
               a.exit.tx === b.exit.tx && a.exit.ty === b.exit.ty;
  check('mesma semente gera masmorra idêntica', same);

  const c = genDungeon(12346, 2);
  check('sementes diferentes geram masmorras diferentes',
    JSON.stringify(a.grid) !== JSON.stringify(c.grid));
}

// ---------------------------------------------------------------- varredura
console.log(`\n=== ${SEEDS} sementes × ${FLOORS.length} andares ===`);

const fail = {
  spawnInWall: [], exitInWall: [], enemyInWall: [], bossInWall: [],
  exitUnreachable: [], enemyUnreachable: [], bossUnreachable: [],
  leakyBorder: [], noRooms: [], enemyOnSpawn: []
};
let totalMaps = 0, totalEnemies = 0, minRooms = Infinity, maxRooms = 0;
let minFloorTiles = Infinity;

for (let s = 1; s <= SEEDS; s++) {
  for (let depth = 0; depth < FLOORS.length; depth++) {
    const seed = s * 977 + depth * 31 + 1;
    const map = genDungeon(seed, depth);
    totalMaps++;
    const tag = `semente ${s}, andar ${depth + 1}`;

    if (!map.rooms.length) { fail.noRooms.push(tag); continue; }
    minRooms = Math.min(minRooms, map.rooms.length);
    maxRooms = Math.max(maxRooms, map.rooms.length);

    let floorTiles = 0;
    for (let y = 0; y < map.gh; y++) for (let x = 0; x < map.gw; x++) if (map.grid[y][x] === FLOOR) floorTiles++;
    minFloorTiles = Math.min(minFloorTiles, floorTiles);

    // borda sólida: um corredor furando o mapa deixaria o jogador sair do mundo
    let leak = false;
    for (let x = 0; x < map.gw; x++) if (map.grid[0][x] === FLOOR || map.grid[map.gh-1][x] === FLOOR) leak = true;
    for (let y = 0; y < map.gh; y++) if (map.grid[y][0] === FLOOR || map.grid[y][map.gw-1] === FLOOR) leak = true;
    if (leak) fail.leakyBorder.push(tag);

    const onFloor = t => map.grid[t.ty] && map.grid[t.ty][t.tx] === FLOOR;

    if (!onFloor(map.spawn)) { fail.spawnInWall.push(tag); continue; }
    if (!onFloor(map.exit)) fail.exitInWall.push(tag);

    const seen = reachable(map, map.spawn);
    const canReach = t => seen[t.ty] && seen[t.ty][t.tx];

    if (!canReach(map.exit)) fail.exitUnreachable.push(tag);

    for (const spot of map.enemySpots) {
      totalEnemies++;
      if (!onFloor(spot)) { fail.enemyInWall.push(tag); continue; }
      if (!canReach(spot)) fail.enemyUnreachable.push(tag);
      // inimigo colado no spawn = dano antes do jogador encostar numa tecla
      const d = Math.hypot(spot.tx - map.spawn.tx, spot.ty - map.spawn.ty);
      if (d < 3) fail.enemyOnSpawn.push(`${tag} (d=${d.toFixed(1)} tiles)`);
    }

    if (map.bossSpot) {
      if (!onFloor(map.bossSpot)) fail.bossInWall.push(tag);
      else if (!canReach(map.bossSpot)) fail.bossUnreachable.push(tag);
    }
  }
}

const show = arr => arr.length ? `${arr.length}×, ex.: ${arr[0]}` : '0';

check('toda masmorra tem pelo menos uma sala', fail.noRooms.length === 0, show(fail.noRooms));
check('borda do mapa sempre sólida', fail.leakyBorder.length === 0, show(fail.leakyBorder));
check('spawn do jogador sempre em chão', fail.spawnInWall.length === 0, show(fail.spawnInWall));
check('escada sempre em chão', fail.exitInWall.length === 0, show(fail.exitInWall));
check('escada sempre alcançável a pé do spawn', fail.exitUnreachable.length === 0, show(fail.exitUnreachable));
check('todo inimigo nasce em chão', fail.enemyInWall.length === 0, show(fail.enemyInWall));
check('todo inimigo alcançável a pé do spawn', fail.enemyUnreachable.length === 0, show(fail.enemyUnreachable));
check('nenhum inimigo nasce colado no spawn', fail.enemyOnSpawn.length === 0, show(fail.enemyOnSpawn));
check('chefe sempre em chão', fail.bossInWall.length === 0, show(fail.bossInWall));
check('chefe sempre alcançável', fail.bossUnreachable.length === 0, show(fail.bossUnreachable));

console.log('\n=== forma das masmorras geradas ===');
console.log(`  mapas gerados      ${totalMaps}`);
console.log(`  inimigos colocados ${totalEnemies}`);
console.log(`  salas por mapa     ${minRooms}..${maxRooms}`);
console.log(`  menor área de chão ${minFloorTiles} tiles`);

// Um andar minúsculo é jogável mas indica gerador degenerado — a maioria das
// tentativas de sala colidindo. 60 tiles é ~2 salas pequenas + corredor.
check('nenhum andar degenerou para área minúscula', minFloorTiles >= 60, `mínimo ${minFloorTiles} tiles`);

console.log(state.failures ? `\n${state.failures} FALHA(S)` : '\nTODOS OS TESTES PASSARAM');
process.exit(state.failures ? 1 : 0);
