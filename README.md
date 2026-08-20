# KelwinKnight — Parte 1: Submundo (demo)

Demo jogável da primeira área do jogo, em **Godot 4.7 / GDScript**. Sem assets:
o mapa, os monstros, os Cavaleiros e o jogador são todos desenhados por código,
na paleta suja do §1.2 (marrom, vermelho escuro, preto, cinza, verde pútrido).

> *"Você acorda em um lugar que não reconhece. Não há instruções. Apenas fome,
> monstros e a certeza de que sair daqui custará mais do que sua vida."*

---

## Rodar

Abra a pasta como projeto no Godot 4.7 e aperte F5. Pela linha de comando:

```bash
godot --path . res://scenes/Main.tscn
```

| Ação | Tecla |
|---|---|
| Mover | `W` `A` `S` `D` ou setas |
| Mirar | mouse (ou a direção do movimento) |
| Atacar | `J` / clique — **segurar** carrega o ataque forte |
| Aparar (parry) | `espaço` / botão direito |
| Dash | `shift` ou `L` |
| Correr | `ctrl` |
| Agachar | `C` |
| Comer um corpo | `E` |
| Inspecionar um Cavaleiro | `F` |
| Alternar arma | `Q` |
| Status | `Tab` |
| Pausar (mostra os controles) | `P` |
| Acordar de novo, depois de morrer | `R` |

Não há tutorial escrito, por decisão do §1.3. O que o jogo ensina, ensina pela
consequência. A tela de pausa lista os controles — isso é referência de
comandos, não tutorial de mecânica.

---

## O que a demo faz

### Resistência é o eixo de tudo (§7.3 + §3.2)

A mecânica central do documento é o parry cobrado pela resistência, e ela está
implementada faixa por faixa. O HUD mostra a faixa atual o tempo todo, porque a
regra é invisível se o jogador não souber em que degrau está.

| Resistência | O que o parry custa |
|---|---|
| 100+ | nada — atordoa e garante o contra-ataque crítico |
| 75-99 | 25% do dano |
| 50-74 | 50% do dano |
| 25-49 | 75% do dano, e 0.3s vulnerável |
| 1-24 | 95% do dano, **não** atordoa, 0.5s vulnerável |
| 0 | o golpe inteiro, e o jogador cai |

Resistência só vem de uma coisa: **comer** (2 por consumo, teto 120). Isso
amarra o §3.2 ao §7.3 — a curva de 51 consumos termina exatamente onde o parry
perfeito começa. Aparar cedo demais ou tarde demais custa 0.5s de
vulnerabilidade, então a janela de 0.2s é uma aposta de verdade.

### O Cavaleiro é uma parede, não um chefe (§5)

O documento diz que **todo golpe de Cavaleiro é mortal com resistência < 100**.
Está implementado ao pé da letra, e isso muda o jogo de lugar: abaixo de 100 não
existe *aparar* um Cavaleiro, porque 25% de um golpe letal continua letal. A
única resposta é o dash, cuja invencibilidade não depende de resistência (§7.2).

Guerra é, na prática, um cronômetro dizendo "você ainda não comeu o bastante".

### O resto do loop

- **Mapa** (§9): um Submundo contínuo, 15-20 salas ligadas por corredores em L,
  gerado por semente. A ligação com a sala anterior mantém o grafo conexo por
  construção — nenhuma sala nasce ilhada, e os testes verificam isso.
- **Spawn** (§2): um monstro brota do chão a cada 10s, teto de 15 vivos. Fugir
  não faz ninguém desaparecer.
- **Mini-boss** (§2): matar 5 monstros em menos de 60s invoca um Cavaleiro.
  Matar devagar não invoca. Derrubar Cavaleiros sobe o teto: 16 → 18 → 21 → 24+.
- **Percepção** (§7.7 / §7.8): cone de 55°, alerta de 0.5s antes da perseguição,
  busca de 5s ao perder de vista. Pedra bloqueia a visão. Golpe pelas costas é
  crítico garantido ×2 e começa o combate com o monstro atordoado.
- **Consumo** (§3.2 / §3.3): a curva de 51 em degraus — desmaio e vômito até 20,
  lentidão até 35, só perda de HP até 50, nada a partir de 51. A primeira vez
  que você come cada criatura destrava a habilidade dela; no 5º consumo da mesma
  criatura o efeito satura.
- **Proficiência** (§7.6): 0/5/15/30/50 usos → +0/+1/+2/+3/+5 de dano, contado
  por ação. O punho e cada arma sobem separados.
- **Combo** (§7.5): +9% por acerto consecutivo, +2% por repetir a mesma ação
  (teto +30%). Levar dano ou passar 2s sem acertar zera.
- **Permadeath** (§2): morrer apaga consumos, habilidades, proficiência,
  inventário e até as armas da alma.

---

## O que a demo **não** faz

Estas partes do GDD ficaram de fora deste recorte. Nenhuma está "meio pronta":

- **Só o 1º Cavaleiro.** Morte, Fome, Peste e Conquista existem como dados
  (HP, arma, Autoridade, habilidade) em `Balance.CAVALEIROS` e já entram na
  rotação conforme você derruba Cavaleiros, mas nenhum tem padrão de ataque
  próprio — todos usam os dois padrões de Guerra.
- **Traditore não existe** (§6). Nada do boss do Submundo foi implementado.
- **As habilidades por consumo são registradas, não usadas.** Comer um
  Rastejador destrava "Visão Sombria", mostra no status e escala até o 5º
  consumo — mas não há Visão Sombria acontecendo no jogo. Vale para as 10.
  O que está implementado é a *economia* do §3.3, não os efeitos do §4.
- **Crafting não existe** (§8). O inventário tem os 2 slots do §3.4 e o peso já
  penaliza a velocidade, mas não há bolsas nem roupas para fabricar, e monstros
  não largam peles.
- **Bloqueio/escudo não existe** (§7.2). Não há escudos no jogo, então a coluna
  "Bloqueio" do §7.4 não tem contraparte. Parry e dash cobrem a defesa.
- **Sem pontos de salvamento** (§9) e sem os eventos fixos roteirizados
  (primeiro desmaio, aparição do Ambutcher).
- **Correr não gasta stamina** — não há stamina no projeto.

### Duas divergências do §10

- O Godot instalado é **4.7.2**, não 4.6.3. O projeto está fixado em 4.7.
- É **GDScript**, não C#. O binário disponível é o build padrão (o de C# seria
  `mono_win64` e traz uma pasta `GodotSharp/`), e o .NET 8 não está instalado.
  O §10.1 já prevê GDScript para protótipo.

---

## Testes

Duas suítes, 147 afirmações. Elas existem porque um número que sai do documento
deve quebrar um teste, não virar bug de gameplay silencioso.

```bash
godot --headless --path . --script res://tests/test_rules.gd
```

**72 afirmações sobre as regras puras.** A tabela de parry faixa por faixa, os
limites da curva de 51, os degraus de proficiência, o combo, o teto de monstros,
e o HP de cada uma das 10 criaturas e dos 5 Cavaleiros conferido contra as
tabelas do §4 e do §5.

```bash
godot --headless --path . res://scenes/Testes.tscn
```

**75 afirmações sobre o comportamento em jogo.** Rodam a cena de verdade em
passo fixo de 1/60 (o teste chama `_process` na mão, então nada depende de
framerate): geração de mapa em 40 sementes com BFS de conectividade, a máquina
de estados da percepção, parede bloqueando visão, o furtivo, o parry medido
contra um golpe real de monstro em cada faixa de resistência, a invencibilidade
do dash, a curva de consumo, o gatilho do mini-boss e o permadeath.

### Playtest automatizado

```bash
godot --path . res://scenes/Captura.tscn -- --saida=C:/algum/lugar
```

Um bot sobe o jogo de verdade, dirige o jogador com eventos de input (não
chamando métodos por dentro), caça monstros, come um cadáver, abre o status,
invoca Guerra e morre para ele — tirando foto em cada etapa. Não use
`--headless`: sem rasterização não há imagem.

Foi ele que encontrou os dois piores problemas desta demo, que nenhum teste de
unidade pegaria: o mapa original de 84×60 tiles deixava o jogador andando ~3
minutos entre encontros com 15 monstros vivos (hoje 64×46, o menor tamanho que
ainda cabe as 15-20 salas do §9 em 200 sementes), e a mira era roubada por um
mouse parado, o que fazia o golpe sair na direção errada para quem joga só de
teclado.

---

## Onde mexer no balanceamento

Quase tudo está em `scripts/core/Balance.gd`, como dado puro e testável:
`PARRY_TIERS`, `consume_effect`, `PROF_USOS`/`PROF_BONUS`, `BESTIARIO`,
`CAVALEIROS`, `SPAWN_INTERVALO`, `monster_cap`, `ATK_LEVE`/`ATK_FORTE`,
`DASH_*`, `CONE_*`.

| Arquivo | Papel |
|---|---|
| `scripts/core/Balance.gd` | todos os números do GDD + as regras puras |
| `scripts/core/GameState.gd` | estado da run; é o que o permadeath zera |
| `scripts/core/Palette.gd` | a paleta do §1.2 |
| `scripts/world/Dungeon.gd` | geração do mapa, colisão e linha de visão |
| `scripts/world/World.gd` | spawn, gatilho do mini-boss, interações, morte |
| `scripts/actors/Player.gd` | ações do §7.2, parry, combo, proficiência |
| `scripts/actors/Enemy.gd` | percepção do §7.7 e ataque telegrafado |
| `scripts/actors/Knight.gd` | Cavaleiro Guerra, Autoridade, janela de 30s |
| `scripts/actors/Figura.gd` | o pintor: todas as figuras saem daqui |
| `scripts/ui/HUD.gd` | HUD, menu de status, tela de morte |
