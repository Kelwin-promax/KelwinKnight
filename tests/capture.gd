extends Node

## Bot de playtest. Sobe a cena real do jogo, dirige o jogador com eventos de
## input de verdade (nao chamando metodos por dentro) e tira fotos nos momentos
## que interessam.
##
##   godot --path . res://scenes/Captura.tscn -- --saida=C:/algum/lugar
##
## Nao usar --headless: sem rasterizacao nao ha imagem para salvar.

var _mundo: Node
var _jogador: Node
var _saida: String = "user://"
var _n: int = 0
var _relato: Array[String] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--saida="):
			_saida = arg.substr(8)
	_mundo = load("res://scenes/Main.tscn").instantiate()
	add_child(_mundo)
	await get_tree().process_frame
	_jogador = _mundo.jogador
	_roteiro()

# ------------------------------------------------------------------ roteiro
func _roteiro() -> void:
	await _esperar(1.6)
	_nota("mapa gerado com %d salas, %d monstros vivos"
			% [_mundo.dungeon.salas.size(), _mundo.monstros_vivos()])
	await _foto("01_acorda")

	# anda um pouco para provar que o movimento e a camera respondem
	await _andar(Vector2(1, 0), 0.8)
	await _andar(Vector2(0, 1), 0.6)
	await _foto("02_explorando")

	# caca: vai ate o monstro mais proximo e bate ate ele cair
	var mortos := 0
	var comeu := false
	var t0 := Time.get_ticks_msec()
	while mortos < 5 and Time.get_ticks_msec() - t0 < 70000 and not _morreu():
		var alvo := _monstro_mais_proximo()
		if alvo == null:
			await _esperar(0.5)
			continue
		var caiu := await _cacar(alvo)
		if not caiu:
			continue
		mortos += 1
		if mortos == 1:
			await _foto("03_combate")
		# 3.2: o corpo esta bem aqui, onde a briga acabou. O bot nao tem
		# pathfinding, entao comer AGORA e a unica forma confiavel -
		# procurar um cadaver longe faz ele andar reto contra a parede.
		if not comeu and is_instance_valid(alvo):
			await _ir_ate(alvo.global_position, 30.0, 4.0)
			if _mundo._cadaver_perto != null:
				await _foto("04_antes_de_comer")
				await _apertar("consumir")
				await _esperar(0.5)
				comeu = true
				_nota("comeu: consumos=%d resistencia=%d desmaiado=%s"
						% [GameState.consumos_total, GameState.resistencia,
						str(_jogador.esta_desmaiado())])
				await _foto("05_desmaio")
				await _esperar(3.4)
	_nota("o bot matou %d monstros em %ds" % [mortos, (Time.get_ticks_msec() - t0) / 1000])
	if not comeu:
		_nota("AVISO: o bot nao conseguiu comer nenhum corpo")

	# menu de status (2) - antes do Cavaleiro, enquanto ainda esta vivo
	if not _morreu():
		Input.action_press("status")
		await _esperar(0.5)
		await _foto("06_status")
		Input.action_release("status")

		await _apertar("pausar")
		await _esperar(0.5)
		await _foto("07_pausa")
		await _apertar("pausar")
		await _esperar(0.3)

	# 5: o Cavaleiro. Se as 5 mortes rapidas ainda nao o invocaram, forco -
	# o gatilho em si ja esta coberto pelos testes de runtime.
	if not _morreu():
		if _cavaleiro() == null:
			_mundo._invocar_cavaleiro()
			_nota("Cavaleiro invocado pelo harness para a foto")
		await _esperar(0.8)
		var k := _cavaleiro()
		if k != null:
			_nota("Guerra: %d HP, golpe = %.0f de dano com resistencia %d"
					% [int(k.hp), k.dano_do_golpe(), GameState.resistencia])
			# Chega perto o bastante para caber na tela, longe o bastante
			# para nao tomar o golpe que, com resistencia < 100, mata.
			await _ir_ate(k.global_position, 190.0, 7.0)
			await _foto("08_cavaleiro_guerra")

	# 2: permadeath. Deixa Guerra matar o jogador e fotografa a tela.
	var espera := Time.get_ticks_msec()
	while not _morreu() and Time.get_ticks_msec() - espera < 25000:
		var k2 := _cavaleiro()
		if k2 != null:
			await _passo_para(k2.global_position - _jogador.global_position, 0.15)
		else:
			await _esperar(0.3)
	_soltar_movimento()
	if _morreu():
		await _esperar(0.6)
		await _foto("09_permadeath")
		_nota("o jogador morreu: %s" % ("morto por Guerra" if _cavaleiro() != null else "morto"))

	print("\n=== RELATO DO PLAYTEST ===")
	for l in _relato:
		print("  " + l)
	print("\nfotos em: " + _saida)
	get_tree().quit(0)

# --------------------------------------------------------------------- bot
## Vai ate o monstro e bate. Devolve true se ele caiu.
func _cacar(alvo: Node) -> bool:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(alvo) and not alvo.morto and not _morreu() \
			and Time.get_ticks_msec() - t0 < 12000:
		var d: Vector2 = alvo.global_position - _jogador.global_position
		if d.length() > 40.0:
			await _passo_para(d, 0.1)
		else:
			_soltar_movimento()
			# encara o alvo antes de bater: a mira segue o movimento
			await _passo_para(d, 0.06)
			_soltar_movimento()
			Input.action_press("atacar")
			await _esperar(0.06)
			Input.action_release("atacar")
			await _esperar(0.3)
	_soltar_movimento()
	return is_instance_valid(alvo) and alvo.morto

func _ir_ate(pos: Vector2, dist: float, limite: float) -> void:
	var t0 := Time.get_ticks_msec()
	while _jogador.global_position.distance_to(pos) > dist \
			and Time.get_ticks_msec() - t0 < int(limite * 1000.0):
		await _passo_para(pos - _jogador.global_position, 0.1)
	_soltar_movimento()

func _passo_para(d: Vector2, dur: float) -> void:
	_soltar_movimento()
	if d.x > 12.0:
		Input.action_press("mover_dir")
	elif d.x < -12.0:
		Input.action_press("mover_esq")
	if d.y > 12.0:
		Input.action_press("mover_baixo")
	elif d.y < -12.0:
		Input.action_press("mover_cima")
	await _esperar(dur)

func _andar(dir: Vector2, dur: float) -> void:
	await _passo_para(dir * 100.0, dur)
	_soltar_movimento()

func _soltar_movimento() -> void:
	for a in ["mover_dir", "mover_esq", "mover_cima", "mover_baixo"]:
		Input.action_release(a)

## `Input.action_press` marca o "just pressed" no frame corrente - se o World
## ja processou esse frame, a acao passa batida. Acoes lidas com
## is_action_just_pressed (comer, inspecionar, pausar) precisam de um evento
## de verdade, que entra na fila e vale o frame inteiro seguinte.
func _apertar(acao: String) -> void:
	var ev := InputEventAction.new()
	ev.action = acao
	ev.pressed = true
	Input.parse_input_event(ev)
	await _esperar(0.1)
	var solta := InputEventAction.new()
	solta.action = acao
	solta.pressed = false
	Input.parse_input_event(solta)
	await _esperar(0.05)

# ------------------------------------------------------------------ buscas
func _monstro_mais_proximo() -> Node:
	var melhor: Node = null
	var d := 1.0e9
	for e in get_tree().get_nodes_in_group("inimigos"):
		if not is_instance_valid(e) or e.morto:
			continue
		var dd: float = e.global_position.distance_to(_jogador.global_position)
		if dd < d:
			d = dd
			melhor = e
	return melhor

func _cadaver_mais_proximo() -> Node:
	var melhor: Node = null
	var d := 1.0e9
	for e in get_tree().get_nodes_in_group("inimigos"):
		if not is_instance_valid(e) or not e.pode_consumir():
			continue
		var dd: float = e.global_position.distance_to(_jogador.global_position)
		if dd < d:
			d = dd
			melhor = e
	return melhor

func _cavaleiro() -> Node:
	for k in get_tree().get_nodes_in_group("cavaleiros"):
		if is_instance_valid(k) and not k.morto:
			return k
	return null

# ------------------------------------------------------------------ apoio
## O jogo pausa a arvore quando o jogador morre. O timer precisa continuar
## rodando mesmo assim, senao o bot congela junto.
func _esperar(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _morreu() -> bool:
	return GameState.hp <= 0.0 or _mundo._morto

func _nota(t: String) -> void:
	_relato.append(t)
	print("[bot] " + t)

func _foto(nome: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var caminho := "%s/%s.png" % [_saida, nome]
	var err := img.save_png(caminho)
	if err != OK:
		push_error("falha ao salvar %s (erro %d)" % [caminho, err])
	else:
		print("[foto] " + caminho)
