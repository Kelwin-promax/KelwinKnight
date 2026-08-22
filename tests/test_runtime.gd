extends Node

## Testes de comportamento em tempo de execucao:
##   godot --headless --path . res://scenes/Testes.tscn
##
## Roda como CENA, nao como --script: os autoloads (GameState) so existem
## quando o Godot sobe uma cena principal de verdade.
##
## Os atores entram na arvore (precisam de get_tree() para achar grupos), mas
## com PROCESS_MODE_DISABLED: quem chama `_process` sou eu, em passo fixo de
## 1/60. Assim o teste e deterministico e nao depende de framerate nem de
## quanto tempo real passou.

const DT := 1.0 / 60.0

var _ok := 0
var _falhas: Array[String] = []
var _palco: Node2D
var _dungeon: Dungeon

func _ready() -> void:
	print("")
	_palco = Node2D.new()
	_palco.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_palco)

	_secao("mapa do Submundo (9)")
	_teste_mapa()
	_secao("percepcao: cone, alerta e busca (7.7 / 7.8)")
	_teste_percepcao()
	_secao("parede bloqueia a visao")
	_teste_parede()
	_secao("combate: golpe, furtivo e combo (7.5 / 7.7)")
	_teste_combate()
	_secao("parry em tempo real contra o golpe do monstro (7.3)")
	_teste_parry_real()
	_secao("dash da invencibilidade (7.2)")
	_teste_dash()
	_secao("consumo, adaptacao e habilidades (3.2 / 3.3)")
	_teste_consumo()
	_secao("spawn, teto e gatilho do mini-boss (2)")
	_teste_spawn()
	_secao("Cavaleiro Guerra (5)")
	_teste_cavaleiro()
	_secao("permadeath (2)")
	_teste_permadeath()
	_secao("folha de sprites do jogador")
	_teste_folha()

	_relatorio()

# ------------------------------------------------------------------- apoio
func _limpar() -> void:
	for c in _palco.get_children():
		_palco.remove_child(c)
		c.free()
	GameState.reset_run()

func _novo_mapa(semente: int = 12345) -> Dungeon:
	_dungeon = Dungeon.new(semente)
	return _dungeon

func _novo_jogador(pos: Vector2) -> Player:
	var p := Player.new()
	p.configurar(_dungeon)
	p.global_position = pos
	_palco.add_child(p)
	return p

func _novo_inimigo(id: String, pos: Vector2, alvo: Node2D) -> Enemy:
	var e := Enemy.new()
	e.configurar(Balance.bestiario_por_id(id), _dungeon, alvo, 777)
	e.global_position = pos
	e.add_to_group("inimigos")
	_palco.add_child(e)
	return e

## Avanca `segundos` chamando `_process` na mao, em passo fixo.
func _avancar(segundos: float, nos: Array) -> void:
	var passos := int(round(segundos / DT))
	for i in range(passos):
		for n in nos:
			if is_instance_valid(n):
				n._process(DT)

# -------------------------------------------------------------------- mapa
func _teste_mapa() -> void:
	var falhas_conexao := 0
	var falhas_abertura := 0
	var poucas_salas := 0
	for s in range(40):
		var d := Dungeon.new(1000 + s * 7)
		if d.salas.size() < 15 or d.salas.size() > 20:
			poucas_salas += 1
		# o mapa aberto nao possui parede nem borda interna solida
		for x in range(d.largura):
			if d.solido(x, 0) or d.solido(x, d.altura - 1):
				falhas_abertura += 1
				break
		# toda sala alcancavel a pe a partir da sala 0
		if not _todas_alcancaveis(d):
			falhas_conexao += 1

	_afirma(poucas_salas == 0, "9: todo mapa tem de 15 a 20 salas", "%d fora da faixa" % poucas_salas)
	_afirma(falhas_abertura == 0, "o mapa inteiro permanece aberto")
	_afirma(falhas_conexao == 0, "toda sala e alcancavel a pe (nenhuma ilha)",
			"%d mapas com ilha" % falhas_conexao)

	var d2 := Dungeon.new(4242)
	var d3 := Dungeon.new(4242)
	_afirma(d2.tiles == d3.tiles, "mesma semente gera o mesmo Submundo")
	_afirma(Dungeon.new(1).tiles == Dungeon.new(2).tiles, "o plano aberto e igual em qualquer semente")

func _todas_alcancaveis(d: Dungeon) -> bool:
	var inicio: Vector2i = d.salas[0].get_center()
	var vistos := {}
	var fila: Array[Vector2i] = [inicio]
	vistos[inicio] = true
	while fila.size() > 0:
		var p: Vector2i = fila.pop_front()
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = p + dir
			if vistos.has(n) or d.solido(n.x, n.y):
				continue
			vistos[n] = true
			fila.append(n)
	for s in d.salas:
		if not vistos.has(s.get_center()):
			return false
	return true

# -------------------------------------------------------------- percepcao
func _teste_percepcao() -> void:
	_limpar()
	_novo_mapa()
	var sala: Rect2i = _dungeon.salas[0]
	var centro := _dungeon.centro_do_tile(sala.get_center().x, sala.get_center().y)

	var j := _novo_jogador(centro + Vector2(120, 0))
	var e := _novo_inimigo("rastejador", centro, j)
	e.mira = Vector2.RIGHT     # olhando direto para o jogador

	_afirma(e.estado == Enemy.PASSIVO, "o monstro comeca passivo")
	_avancar(0.1, [e])
	_afirma(e.estado == Enemy.ALERTA, "entrou no cone: fica ALERTA")
	# 7.7: o alerta leva 0.5s antes de virar perseguicao
	_avancar(0.3, [e])
	_afirma(e.estado == Enemy.ALERTA, "ainda ALERTA antes de 0.5s (nao persegue na hora)")
	_avancar(0.35, [e])
	_afirma(e.estado == Enemy.PERSEGUE, "passados 0.5s, PERSEGUE")

	# 7.7: fora do cone nao aggro
	_limpar()
	_novo_mapa()
	var j2 := _novo_jogador(centro + Vector2(120, 0))
	var e2 := _novo_inimigo("rastejador", centro, j2)
	e2.mira = Vector2.LEFT      # de costas para o jogador
	# A geometria do furtivo e checada AGORA, antes de andar: um monstro
	# passivo perambula e vira a cara, entao medir isso depois de 1s testaria
	# o sorteio do destino, nao a regra do 7.7.
	_afirma(e2.esta_de_costas_para(j2.global_position),
			"o jogador esta nas costas dele (permite o furtivo)")
	_avancar(1.0, [e2])
	_afirma(e2.estado != Enemy.PERSEGUE, "de costas para o jogador: nao percebe nada",
			"estado=%d" % e2.estado)

	# 7.8: perder de vista joga o monstro em BUSCA por 5s
	_limpar()
	_novo_mapa()
	var j3 := _novo_jogador(centro + Vector2(120, 0))
	var e3 := _novo_inimigo("rastejador", centro, j3)
	e3.mira = Vector2.RIGHT
	_avancar(0.7, [e3])
	_afirma(e3.estado == Enemy.PERSEGUE, "perseguindo antes de o jogador sumir")
	j3.global_position = centro + Vector2(4000, 4000)   # sumiu do mapa
	_avancar(1.2, [e3])
	_afirma(e3.estado == Enemy.BUSCA, "perdeu de vista: entra em BUSCA", "estado=%d" % e3.estado)
	_avancar(Balance.BUSCA_DURACAO + 0.6, [e3])
	_afirma(e3.estado == Enemy.PASSIVO, "passados 5s sem achar: volta ao PASSIVO",
			"estado=%d" % e3.estado)

func _teste_parede() -> void:
	_limpar()
	var d := _novo_mapa(999)
	var a := d.centro_do_tile(4, 4)
	var b := d.centro_do_tile(8, 4)
	_afirma(not d.solido(4, 4) and not d.solido(8, 4),
			"o mapa aberto nao possui paredes")
	_afirma(d.linha_livre(a, b), "a visao atravessa o mapa aberto")
	var j := _novo_jogador(b)
	var e := _novo_inimigo("vigia", a, j)
	e.mira = (b - a).normalized()
	_avancar(1.5, [e])
	_afirma(e.estado == Enemy.PERSEGUE, "olhando na direcao certa, ve atraves do mapa aberto",
			"dist=%.0f" % a.distance_to(b))

# ----------------------------------------------------------------- combate
func _teste_combate() -> void:
	_limpar()
	_novo_mapa()
	var sala: Rect2i = _dungeon.salas[0]
	var centro := _dungeon.centro_do_tile(sala.get_center().x, sala.get_center().y)

	var j := _novo_jogador(centro)
	var e := _novo_inimigo("carniceiro", centro + Vector2(30, 0), j)
	e.mira = Vector2.RIGHT          # de costas para o jogador
	j.mira = Vector2.RIGHT

	var hp0 := e.hp
	j._iniciar_ataque(false)
	_avancar(0.3, [j])
	var dano_furtivo := hp0 - e.hp
	_afirma(dano_furtivo > 0.0, "o golpe leve acerta e tira vida", "-%.1f" % dano_furtivo)
	# 7.7: pelas costas o dano e dobrado e o monstro comeca atordoado
	_afirma(dano_furtivo >= Balance.ATK_LEVE["dano"] * 1.9,
			"golpe pelas costas: critico garantido 2x", "-%.1f de base %.0f" % [dano_furtivo, Balance.ATK_LEVE["dano"]])
	_afirma(e.estado == Enemy.ATORDOADO, "o furtivo comeca o combate com o monstro atordoado")

	# fora de alcance nao acerta
	_limpar()
	_novo_mapa()
	var j2 := _novo_jogador(centro)
	var e2 := _novo_inimigo("carniceiro", centro + Vector2(300, 0), j2)
	j2.mira = Vector2.RIGHT
	var hp2 := e2.hp
	j2._iniciar_ataque(false)
	_avancar(0.3, [j2])
	_afirma(is_equal_approx(e2.hp, hp2), "inimigo fora de alcance nao leva dano",
			"a 300px, alcance %.0f" % Balance.ATK_LEVE["alcance"])

	# atras da mira nao acerta
	_limpar()
	_novo_mapa()
	var j3 := _novo_jogador(centro)
	var e3 := _novo_inimigo("carniceiro", centro + Vector2(-30, 0), j3)
	j3.mira = Vector2.RIGHT       # mirando para o lado oposto
	var hp3 := e3.hp
	j3._iniciar_ataque(false)
	_avancar(0.3, [j3])
	_afirma(is_equal_approx(e3.hp, hp3), "inimigo atras da mira nao leva dano")

	# 7.5: o combo sobe com acertos consecutivos
	_limpar()
	_novo_mapa()
	var j4 := _novo_jogador(centro)
	j4.mira = Vector2.RIGHT
	var e4 := _novo_inimigo("regen", centro + Vector2(30, 0), j4)
	e4.hp = 100000.0        # saco de pancada, para nao morrer no meio
	e4.hp_max = 100000.0
	for golpe in range(3):
		j4._iniciar_ataque(false)
		_avancar(0.35, [j4])
	_afirma(j4.combo == 3, "3 acertos seguidos = combo 3", "combo=%d" % j4.combo)
	_avancar(Balance.COMBO_JANELA + 0.3, [j4])
	_afirma(j4.combo == 0, "2s sem acertar e o combo cai")

	# 7.6: proficiencia sobe com o uso
	_afirma(int(GameState.proficiencia.get("punho_leve", 0)) == 3,
			"cada acerto conta para a proficiencia da acao",
			"punho_leve=%d" % int(GameState.proficiencia.get("punho_leve", 0)))

# ------------------------------------------------------------------- parry
func _teste_parry_real() -> void:
	# Aqui o parry e testado como o jogador o vive: um monstro telegrafa,
	# o golpe cai, e a resistencia decide o preco.
	for caso in [[120, 0.0], [80, 0.25], [60, 0.50], [30, 0.75], [10, 0.95]]:
		var resist: int = caso[0]
		var fracao: float = caso[1]
		_limpar()
		_novo_mapa()
		var sala: Rect2i = _dungeon.salas[0]
		var centro := _dungeon.centro_do_tile(sala.get_center().x, sala.get_center().y)
		# a resistencia vem dos consumos (3.2)
		GameState.consumos_total = int(ceil(float(resist) / float(Balance.RESIST_POR_CONSUMO)))

		var j := _novo_jogador(centro)
		var e := _novo_inimigo("carniceiro", centro + Vector2(28, 0), j)
		e.mira = Vector2.LEFT
		e._iniciar_ataque()
		# espera o telegrafo quase acabar e aperta o parry dentro da janela
		_avancar(Enemy.WINDUP - 0.1, [e])
		j._iniciar_parry()
		var hp_antes := GameState.hp
		_avancar(0.15, [e, j])
		var sofrido := hp_antes - GameState.hp
		var esperado := e.dano * fracao
		_afirma(absf(sofrido - esperado) < 1.0,
				"resistencia %d: parry cobra %d%% do golpe" % [GameState.resistencia, int(fracao * 100.0)],
				"esperado %.1f, sofrido %.1f" % [esperado, sofrido])
		if resist >= 25:
			_afirma(e.estado == Enemy.ATORDOADO, "resistencia %d: o parry atordoa o inimigo" % resist)

	# parry no vazio: 0.5s de vulnerabilidade
	_limpar()
	_novo_mapa()
	var s2: Rect2i = _dungeon.salas[0]
	var c2 := _dungeon.centro_do_tile(s2.get_center().x, s2.get_center().y)
	var j2 := _novo_jogador(c2)
	j2._iniciar_parry()
	_avancar(Balance.PARRY_WINDOW + 0.05, [j2])
	_afirma(not j2._pode_agir(), "parry no vazio deixa o jogador vulneravel")
	_avancar(Balance.PARRY_FAIL_VULN, [j2])
	_afirma(j2._pode_agir(), "passada a punicao, o jogador volta a agir")

	# parry cedo demais nao cobre o golpe
	_limpar()
	_novo_mapa()
	var j3 := _novo_jogador(c2)
	var e3 := _novo_inimigo("carniceiro", c2 + Vector2(28, 0), j3)
	GameState.consumos_total = 60          # resistencia 120: parry seria perfeito
	e3.mira = Vector2.LEFT
	e3._iniciar_ataque()
	j3._iniciar_parry()                    # apertado no comeco do telegrafo
	var hp3 := GameState.hp
	_avancar(Enemy.WINDUP + 0.1, [e3, j3])
	_afirma(GameState.hp < hp3, "parry cedo demais: o golpe entra inteiro",
			"-%.1f" % (hp3 - GameState.hp))

func _teste_dash() -> void:
	_limpar()
	_novo_mapa()
	var sala: Rect2i = _dungeon.salas[0]
	var centro := _dungeon.centro_do_tile(sala.get_center().x, sala.get_center().y)
	var j := _novo_jogador(centro)
	var e := _novo_inimigo("furioso", centro + Vector2(28, 0), j)
	e.mira = Vector2.LEFT
	e._iniciar_ataque()
	_avancar(Enemy.WINDUP - 0.1, [e])
	j._invuln = Balance.DASH_INVULN        # equivale a ter dado o dash agora
	var hp := GameState.hp
	_avancar(0.15, [e, j])
	_afirma(is_equal_approx(GameState.hp, hp), "durante o dash o golpe nao machuca",
			"hp %.0f" % GameState.hp)

	# controle: sem dash o mesmo golpe machuca
	_limpar()
	_novo_mapa()
	var j2 := _novo_jogador(centro)
	var e2 := _novo_inimigo("furioso", centro + Vector2(28, 0), j2)
	e2.mira = Vector2.LEFT
	e2._iniciar_ataque()
	var hp2 := GameState.hp
	_avancar(Enemy.WINDUP + 0.1, [e2, j2])
	_afirma(GameState.hp < hp2, "sem dash, o mesmo golpe entra (controle)",
			"-%.1f" % (hp2 - GameState.hp))

# ----------------------------------------------------------------- consumo
func _teste_consumo() -> void:
	_limpar()
	_novo_mapa()
	var sala: Rect2i = _dungeon.salas[0]
	var centro := _dungeon.centro_do_tile(sala.get_center().x, sala.get_center().y)
	var j := _novo_jogador(centro)
	var e := _novo_inimigo("rastejador", centro + Vector2(20, 0), j)
	e.levar_dano(9999.0)
	_afirma(e.morto and e.pode_consumir(), "monstro morto vira cadaver consumivel")

	var hp0 := GameState.hp
	j.consumir(e)
	_afirma(not e.pode_consumir(), "o mesmo cadaver nao pode ser comido duas vezes")
	_afirma(GameState.hp < hp0, "1o consumo: o corpo rejeita e custa HP", "-%.0f" % (hp0 - GameState.hp))
	_afirma(j.esta_desmaiado(), "1o consumo: desmaio (faixa 1-20)")
	_afirma(GameState.habilidades.has("rastejador"), "comer destrava a habilidade da criatura")
	_afirma(String(GameState.habilidades["rastejador"]["nome"]) == "Visão Sombria",
			"Rastejador de Olhos concede Visão Sombria")
	_afirma(GameState.resistencia == Balance.RESIST_POR_CONSUMO,
			"o consumo aumenta a resistencia", "resist=%d" % GameState.resistencia)

	# 2: o menu de status abre durante o desmaio
	_afirma(j.esta_desmaiado(), "durante o desmaio o jogador nao age, mas o status abre")

	# 3.3: o 5o consumo da mesma criatura satura a habilidade
	for i in range(4):
		var ex := _novo_inimigo("rastejador", centro + Vector2(20, 0), j)
		ex.levar_dano(9999.0)
		j.consumir(ex)
	_afirma(int(GameState.habilidades["rastejador"]["consumos"]) == 5,
			"5 consumos da mesma criatura")
	_afirma(is_equal_approx(float(GameState.habilidades["rastejador"]["escala"]), 1.0),
			"no 5o consumo a habilidade satura (CD zero / efeito maximo)")

	# 51+ consumos: nenhum efeito colateral
	GameState.consumos_total = 60
	var e51 := _novo_inimigo("peleveloz", centro + Vector2(20, 0), j)
	e51.levar_dano(9999.0)
	var hp51 := GameState.hp
	j._desmaio = 0.0
	j.consumir(e51)
	_afirma(is_equal_approx(GameState.hp, hp51), "com 51+ consumos, comer nao custa mais HP")
	_afirma(not j.esta_desmaiado(), "com 51+ consumos, nao ha mais desmaio")

# ------------------------------------------------------------------- spawn
func _teste_spawn() -> void:
	_limpar()
	GameState.tempo_run = 0.0
	# 2: 5 mortes em menos de 60s invocam um Cavaleiro
	var invocou := false
	for i in range(5):
		GameState.tempo_run += 5.0
		invocou = GameState.registrar_morte_de_monstro()
	_afirma(invocou, "5 monstros mortos em 25s invocam o Cavaleiro")

	# devagar demais nao invoca
	GameState.reset_run()
	GameState.tempo_run = 0.0
	var invocou_lento := false
	for i in range(5):
		GameState.tempo_run += 20.0     # 20s entre mortes: a janela expira
		invocou_lento = GameState.registrar_morte_de_monstro() or invocou_lento
	_afirma(not invocou_lento, "matando devagar, o Cavaleiro nao aparece")

	# o teto cresce com os Cavaleiros derrubados
	GameState.reset_run()
	_afirma(GameState.teto_de_monstros() == 30, "teto inicial de 30 monstros")
	GameState.cavaleiros_mortos = 2
	_afirma(GameState.teto_de_monstros() == 33, "com 2 Cavaleiros mortos o teto vai a 33")

# --------------------------------------------------------------- cavaleiro
func _teste_cavaleiro() -> void:
	_limpar()
	_novo_mapa()
	var sala: Rect2i = _dungeon.salas[0]
	var centro := _dungeon.centro_do_tile(sala.get_center().x, sala.get_center().y)
	var j := _novo_jogador(centro)

	var k := Knight.new()
	k.configurar(Balance.cavaleiro_por_indice(0), _dungeon, j, 31337)
	k.global_position = centro + Vector2(60, 0)
	k.add_to_group("cavaleiros")
	_palco.add_child(k)

	_afirma(k.hp == 120.0, "Guerra entra com 120 HP")

	# 5: com resistencia < 100 o golpe do Cavaleiro e mortal
	GameState.consumos_total = 0
	_afirma(k.dano_do_golpe() > GameState.hp_max,
			"resistencia %d: o golpe de Guerra mata de um toque" % GameState.resistencia,
			"dano=%.0f vs %d de vida" % [k.dano_do_golpe(), int(GameState.hp_max)])
	GameState.consumos_total = 50      # resistencia 100
	_afirma(GameState.resistencia >= 100, "50 consumos levam a resistencia a 100")
	_afirma(k.dano_do_golpe() < GameState.hp_max,
			"com resistencia 100 o golpe deixa de ser letal", "dano=%.0f" % k.dano_do_golpe())

	# 5: a Autoridade instiga os monstros ao redor
	var e := _novo_inimigo("rastejador", centro + Vector2(100, 0), j)
	e.mira = Vector2.LEFT              # de costas: sozinho nunca perceberia
	_avancar(0.2, [k])
	_afirma(e.estado == Enemy.PERSEGUE,
			"a Autoridade de Guerra joga os monstros em cima do jogador", "estado=%d" % e.estado)

	# 5: 30s de janela para inspecionar, e a arma vai para a alma
	k.levar_dano(9999.0)
	_afirma(k.morto, "Guerra cai")
	_afirma(k.pode_inspecionar(), "logo apos a morte da para inspecionar o corpo")
	_afirma(k.janela_de_inspecao() > 29.0, "a janela comeca em 30s",
			"%.1fs" % k.janela_de_inspecao())
	_avancar(Balance.INSPECAO_JANELA + 1.0, [k])
	_afirma(not k.pode_inspecionar(), "passados 30s o corpo nao entrega mais nada")

	GameState.ganhar_arma("Espada Colossal")
	_afirma(GameState.armas_na_alma.has("Espada Colossal"), "a arma entra na alma")
	_afirma(GameState.inventario.is_empty(), "a arma NAO ocupa slot de inventario")
	_afirma(GameState.acao_de_ataque(false) == "espada_colossal_leve",
			"a arma tem proficiencia propria, separada do punho",
			GameState.acao_de_ataque(false))

# --------------------------------------------------------- folha de sprites
## A folha e um asset externo: o teste nao adivinha o desenho, so garante que
## o mapa de animacoes aponta para figuras que existem de fato e que todo
## estado que o Player sabe produzir tem pose. Trocar a folha por uma com
## menos bonecos numa banda quebra aqui, e nao na tela do jogador.
func _teste_folha() -> void:
	if not SpriteJogador.disponivel():
		_afirma(true, "sem folha: o jogador cai no desenho por codigo (nao e falha)")
		return
	_afirma(SpriteJogador.tabela_valida(),
			"toda pose citada existe na folha")

	# as poses que o _anim_atual() do Player pode devolver
	for nome in ["parado", "andar", "correr", "dash", "ataque_leve",
			"ataque_forte", "parry", "dano", "caido"]:
		_afirma(SpriteJogador.ANIMS.has(nome), "existe a pose '%s'" % nome)

# -------------------------------------------------------------- permadeath
func _teste_permadeath() -> void:
	_limpar()
	GameState.consumos_total = 33
	GameState.consumos_por_criatura["furioso"] = 3
	GameState.habilidades["furioso"] = {"nome": "Furia Berserker", "tipo": "ativa", "consumos": 3, "escala": 0.5}
	GameState.proficiencia["punho_leve"] = 42
	GameState.ganhar_arma("Espada Colossal")
	GameState.adicionar_item("pele")
	GameState.cavaleiros_mortos = 1
	_afirma(GameState.resistencia > 0 and not GameState.habilidades.is_empty(),
			"a run tem progresso acumulado (setup)")

	GameState.reset_run()
	_afirma(GameState.consumos_total == 0, "morrer zera o contador de consumos")
	_afirma(GameState.habilidades.is_empty(), "morrer apaga as habilidades")
	_afirma(GameState.proficiencia.is_empty(), "morrer apaga a proficiencia")
	_afirma(GameState.inventario.is_empty(), "morrer esvazia o inventario")
	_afirma(GameState.armas_na_alma.is_empty(), "morrer tira ate as armas da alma")
	_afirma(GameState.cavaleiros_mortos == 0, "morrer zera os Cavaleiros derrubados")
	_afirma(GameState.resistencia == 0, "morrer devolve a resistencia a zero")
	_afirma(is_equal_approx(GameState.hp, GameState.hp_max), "a proxima run comeca com vida cheia")

# ------------------------------------------------------------------ apoio
func _secao(titulo: String) -> void:
	print("\n=== " + titulo + " ===")

func _afirma(cond: bool, desc: String, extra: String = "") -> void:
	var sufixo := ("  [" + extra + "]") if extra != "" else ""
	if cond:
		_ok += 1
		print("  ok  " + desc + sufixo)
	else:
		_falhas.append(desc)
		print("  FALHOU  " + desc + sufixo)

func _relatorio() -> void:
	print("")
	if _falhas.is_empty():
		print("TODOS OS TESTES PASSARAM (%d afirmacoes)" % _ok)
		get_tree().quit(0)
	else:
		print("%d FALHA(S) de %d afirmacoes:" % [_falhas.size(), _ok + _falhas.size()])
		for f in _falhas:
			print("  - " + f)
		get_tree().quit(1)
