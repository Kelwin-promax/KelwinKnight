# Corte Seco

Protótipo jogável de ação/plataforma em HTML5 Canvas, arquivo único, feito para
testar progressão de dificuldade e mecânica de combate. Sem assets: cenário e
personagens são desenhados por código. Sem save nem persistência.

## Como rodar

Abra `corte-seco.html` direto no navegador. Não precisa de servidor nem build.

| Ação | Teclas |
|---|---|
| Mover | `A` `D` ou setas |
| Pular | `W` ou `Espaço` (segurar sobe mais) |
| Dash | `Shift` ou `L` (dá invencibilidade) |
| Atacar | `J`, `K` ou clique |
| Pausar | `P` |

## Estrutura do jogo

Cinco níveis fixos. Elimine todos os inimigos para avançar; a morte reinicia
apenas o nível atual, e os anteriores continuam liberados.

1. **Tutorial** — arena fechada, 1 alvo fraco, sem risco real de morte
2. **Corredor leste** — 2 grunts, primeiro vão
3. **Vãos duplos** — 3 inimigos, o terceiro mais rápido
4. **Quebra-costas** — 5 inimigos, incluindo 2 rápidos e 1 pesado
5. **O Executor** — chefe com dois padrões alternados (investida e salva de
   projéteis), cada um telegrafado pelo emblema no peito

## Onde ajustar o balanceamento

Tudo fica no topo do `<script>`:

- `TYPES` — vida, velocidade, dano e alcance de aggro por tipo de inimigo
- `LEVELS` — layout, plataformas, inimigos e o multiplicador `agg`, que escala
  velocidade e dano por nível
- `BOSS` — vida e parâmetros dos dois padrões
- Constantes de física: `GRAVITY`, `JUMP_V`, `DASH_*`, `ATK_*`

## Testes

Rodam em Node com um stub de DOM/Canvas, sem navegador:

```bash
node harness.js
```

- `harness.js` — bot joga do nível 1 até a vitória; mede tempo, dano e mortes
  por nível, e acusa inimigo que caia em buraco
- `reach.js` — verifica analiticamente se toda plataforma é alcançável e se
  alguma laje bloqueia a travessia de um vão
- `jumptest.js` — simula o pulo real em cada plataforma e confirma o pouso
- `bugtest.js` — testes focados: detecção de borda da IA e latência do ataque

Os scripts `make-shots.js`, `make-sheet.js` e `make-zoom.js` geram páginas de
inspeção visual para screenshot em Chrome headless.

## Estado atual

Todos os testes passam. No playthrough automatizado o bot completa os cinco
níveis sem morrer, com a curva de dano subindo de 0 (tutorial) até ~66 (chefe).

Duas ressalvas conhecidas:

- O bot de teste não substitui playtest humano. Ele usa toques repetidos de
  tecla, então ritmo de combate, dash e pulo de altura variável só dão para
  avaliar jogando de verdade.
- Remover a latência do ataque deixou o jogo bem mais fácil, sobretudo o chefe:
  no bot, o nível 5 caiu de ~40s e 2-3 mortes para ~13s e nenhuma morte. Se a
  intenção for manter o chefe como uma parede, vale subir `BOSS.maxHp` ou a
  agressividade dele.
