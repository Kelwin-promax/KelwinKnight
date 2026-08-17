# Corte Seco

Dois protótipos jogáveis em HTML5 Canvas, arquivo único, sem assets — cenário e
personagens são desenhados por código, e nada é salvo em disco.

| Arquivo | O que é | Estado |
|---|---|---|
| `corte-seco-rl.html` | Roguelike top-down, masmorra procedural, permadeath | **atual** |
| `corte-seco.html` | Plataforma lateral, 5 níveis fixos | referência |

Os dois compartilham o mesmo gerador de sprites, a mesma paleta e o mesmo núcleo
de combate. O que muda é o mundo: um tem gravidade e plataformas, o outro é uma
planta baixa em grade.

---

## Corte Seco · Masmorra (top-down)

Abra `corte-seco-rl.html` direto no navegador. Não precisa de servidor nem build.

| Ação | Teclas |
|---|---|
| Mover (8 direções) | `W` `A` `S` `D` ou setas |
| Mirar | direção do movimento, ou o mouse |
| Dash | `Shift` ou `L` (dá invencibilidade) |
| Atacar | `J`, `K` ou clique |
| Pausar | `P` |

### Estrutura de uma run

Cinco andares gerados por semente. Elimine todos os inimigos para a escada
abrir, desça, repita. **Morrer encerra a run inteira** — a próxima começa do
andar 1 numa masmorra nova. Não há upgrades nem progressão entre runs.

1. **Cripta rasa** — 5 salas, 4 inimigos, um deles inofensivo
2. **Galerias** — 6 salas, 6 inimigos, entra o `runner`
3. **Cisternas** — 7 salas, 8 inimigos, entra o `brute`
4. **Ossário** — 8 salas, 10 inimigos, dois `brute`
5. **O Executor** — arena única, chefe com dois padrões alternados (investida
   com rumo travado e telegrafado, e salva radial de projéteis em 3 ondas)

A semente da run aparece no HUD. Depois de morrer, **Repetir semente** joga a
mesma masmorra de novo — é o que torna uma morte injusta investigável.

### Como a masmorra é gerada

`genDungeon(seed, depth)` é uma função pura: mesma semente, mesma masmorra, e
nenhuma dependência de canvas. Salas retangulares sem sobreposição, ligadas em
cadeia por corredores em L.

Ligar cada sala à **anterior** é o que garante conectividade por construção — o
grafo é uma árvore, então toda sala alcança a sala 0. Os elos extras sorteados
depois só criam atalhos, nunca ilhas. `rl-dungeon.js` verifica isso em 2000
mapas em vez de confiar no argumento.

### Onde ajustar o balanceamento

Tudo no topo do `<script>`:

- `TYPES` — vida, velocidade, dano, raio e alcance de aggro por tipo
- `FLOORS` — tamanho da grade, nº de salas, `count`/`mix` de inimigos e o
  multiplicador `agg`, que escala velocidade e dano por andar
- `BOSS` — vida e parâmetros dos dois padrões
- Combate: `ATK_RANGE`, `ATK_ARC`, `ATK_DMG`, `DASH_*`, `MOVE_ACCEL`, `MAX_SPEED`

### Testes

Rodam em Node com um stub de DOM/Canvas, sem navegador:

```bash
node rl-dungeon.js
```

- `rl-stub.js` — stub de DOM/Canvas + BFS de tiles, compartilhado pelos três
- `rl-dungeon.js` — 400 sementes × 5 andares: afirma que spawn, escada, inimigos
  e chefe caem em chão e são alcançáveis a pé, que a borda do mapa não vaza e
  que a maior pegada de inimigo cabe no corredor mais estreito
- `rl-harness.js` — bot com pathfinding desce os cinco andares; mede tempo e
  dano por andar e testa o permadeath
- `rl-bugtest.js` — latência e arco do ataque, cadência, colisão com parede em
  velocidade de dash, linha de visão da IA e invencibilidade do dash

### Rigs de inspeção visual

Geram páginas para screenshot em Chrome headless — o painel de browser embutido
não serve, porque com a aba oculta o `requestAnimationFrame` não dispara e o
loop nunca começa.

- `make-rl-shots.js` — uma cena por andar, jogador posicionado perto da ação
- `make-rl-zoom.js` — o elenco todo ampliado, para julgar o pixel art de perto
- `make-rl-play.js` — o jogo com um bot embutido disparando eventos de teclado
  reais; `?frames=N` escolhe o momento capturado

O rig de partida simula em **passo fixo síncrono**, não por `requestAnimationFrame`.
Em headless o rAF dispara pouquíssimas vezes mesmo com `--virtual-time-budget`
alto, e como o jogo trava `dt` em 1/30s, uma captura nominalmente em "75s"
mostrava 0.2s de jogo. Ele também neutraliza o `requestAnimationFrame` antes do
laço: sem isso o rAF real volta com um timestamp atrás do relógio sintético,
`dt` sai negativo e o jogo anda para trás — o flash de dano decai por
`flash - dt*3`, então com `dt` negativo ele cresce e satura a tela de vermelho.

### Sprites

Jogador e inimigos têm **64×104px** — grade de 16×26 células a 4px (`PX`). O
chefe usa moldura própria, 26×38 células (104×152px), para dominar a arena de
relance.

Todos compartilham a MESMA moldura de 16×26: o porte vem de `bulk`, que
engrossa tronco e ombros dentro dela. Molduras diferentes por tipo achatariam o
`runner` e cortariam o `brute`.

Todas as figuras saem do mesmo pintor paramétrico (`paintFigure`), então
jogador e inimigos compartilham a linguagem visual: contorno escuro, capuz ou
boné, cinto de couro, botas. Os flags por personagem ficam em `SPECS`:
`hood`, `horns`, `crest`, `emblem`, `beard`, `brim`, `bulk`.

O tile do mundo é 64px e **tudo medido em pixels por segundo foi escalado pelo
mesmo fator 1.6** — velocidade, dash, alcance do golpe, knockback, projéteis.
Sem isso o personagem ficaria grande e lento. O harness confirma: os tempos por
andar praticamente não mudaram com a troca de escala.

A pegada de colisão é bem menor que o desenho (jogador: 42px de pegada para
64px de corpo). O sprite passa por cima da parede ao encostar nela, que é a
leitura certa em 3/4 — o personagem fica na frente da pedra, não dentro. O
`brute` é o gargalo: 60px de pegada num corredor de 64px, e `rl-dungeon.js`
afirma essa folga.

O jogador segue uma sprite sheet de referência fornecida — boné azul-marinho
com aba, túnica mostarda com brasão claro no peito, calça azul, espadão de
lâmina escura. É **referência de paleta e silhueta**, não cópia de pixels: nada
da imagem original entra no repositório. Se aquela arte for licenciada de
terceiros, convém verificar os direitos antes de publicar algo que a copie de
perto.

Isso também resolveu um problema de leitura: com a paleta antiga o jogador era
mais um vulto marrom-avermelhado no meio de encapuzados marrom-avermelhados.

### Estado atual

Todos os testes passam. No playthrough automatizado o bot completa os cinco
andares sem morrer.

| Andar | Tempo | Dano sofrido |
|---|---|---|
| 1 · Cripta rasa | 12.2s | 0 |
| 2 · Galerias | 13.2s | 0 |
| 3 · Cisternas | 20.4s | 0 |
| 4 · Ossário | 23.3s | 0 |
| 5 · O Executor | 11.8s | 60 |

Ressalvas conhecidas:

- **A curva está chata nos andares 1-4.** O bot atravessa quatro andares sem
  tomar um golpe, e a causa é estrutural: o alcance do golpe é 52px, enquanto o
  dano por encostar só acontece a ~29px. A espada supera o inimigo em alcance
  por larga margem, então dá para picar tudo de fora. O ajuste não é subir
  `agg` — é reduzir `ATK_RANGE` ou dar aos inimigos um ataque próprio com
  alcance e telegrafia, em vez de dano por contato.
- O bot de teste não substitui playtest humano. Ele usa toques repetidos de
  tecla e pathfinding perfeito, então ritmo de combate, mira com mouse e uso do
  dash só dão para avaliar jogando de verdade.

---

## Corte Seco (plataforma lateral) — referência

Abra `corte-seco.html` no navegador. Controles e estrutura no histórico do git
(commit `d06642c`). Cinco níveis fixos, morrer reinicia só o nível atual.

Testes: `node harness.js`, `node reach.js`, `node jumptest.js`, `node bugtest.js`.

Dois problemas conhecidos, não corrigidos:

- **Os testes quebram em checkout Windows.** Com `core.autocrlf=true` e sem
  `.gitattributes`, o HTML chega com CRLF e a âncora de injeção em `harness.js`
  e `make-shots.js` — escrita com `\n` literal — não casa. Corrigir com
  `.replace(/\r\n/g, '\n')` na leitura, como faz `rl-stub.js`.
- **Falta `<meta charset>`.** Por `file://` o Chrome adivinha UTF-8 e os acentos
  saem certos; servido por HTTP sem header de charset, quebra.
