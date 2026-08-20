extends Node2D

## O Submundo (9). Um mapa continuo, monstros que brotam do chao a cada 10s
## e nunca despawnam, e um Cavaleiro que aparece quando voce mata rapido
## demais (2). Nao ha tutorial escrito (1.3): o que o jogo ensina, ensina
## pela consequencia.

const CENA_INIMIGO := preload("res://scripts/actors/Enemy.gd")
const CENA_JOGADOR := preload("res://scripts/actors/Player.gd")
const CENA_CAVALEIRO := preload("res://scripts/actors/Knight.gd")

var dungeon: Dungeon
var mapa: MapaVisual
var jogador: Player
var camera: Camera2D
var hud: HUD
var capa: CanvasLayer

var _rng := RandomNumberGenerator.new()
var _t_spawn: float = 0.0
var _semente: int = 0
var _morto: bool = false
var _pausado: bool = false
var _fade: float = 1.0
var _cadaver_perto: Node = null
var _cavaleiro_perto: Knight = null

func _ready() -> void:
	# Precisa continuar processando com a arvore pausada, senao o proprio
	# P que pausou nunca mais e lido - e o R da tela de morte tambem nao.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_registrar_inputs()
	randomize()
	_semente = randi()
	_montar()

# --------------------------------------------------------------- montagem
func _montar() -> void:
	# remove_child antes do free: queue_free e adiado, e o $Atores novo
	# esbarraria no antigo ainda pendurado na arvore.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	get_tree().paused = false
	_pausado = false

	_rng.seed = _semente
	dungeon = Dungeon.new(_semente)

	mapa = MapaVisual.new()
	mapa.configurar(dungeon)
	add_child(mapa)

	var atores := Node2D.new()
	atores.name = "Atores"
	atores.y_sort_enabled = true
	add_child(atores)

	jogador = CENA_JOGADOR.new()
	jogador.configurar(dungeon)
	jogador.global_position = dungeon.chao_aleatorio(_rng)
	jogador.morreu.connect(_ao_morrer)
	jogador.acao_relevante.connect(func(t, c): GameState.mensagem(t, c))
	jogador.desmaiou.connect(func(_d): GameState.mensagem("Voce desmaia", Palette.ALERTA))
	atores.add_child(jogador)

	camera = Camera2D.new()
	camera.zoom = Vector2(1.7, 1.7)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(dungeon.tamanho_px().x)
	camera.limit_bottom = int(dungeon.tamanho_px().y)
	jogador.add_child(camera)
	camera.make_current()

	capa = CanvasLayer.new()
	add_child(capa)
	hud = HUD.new()
	hud.jogador = jogador
	hud.mundo = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	capa.add_child(hud)

	# Populacao inicial. Sem isso o comeco e uma caminhada silenciosa:
	# o spawn do 2 so entrega um monstro a cada 10s.
	for i in range(10):
		_nascer_monstro(false)

	_t_spawn = 0.0
	_morto = false
	_fade = 1.0
	hud.mostrar_morte(false)
	GameState.mensagem("Você acorda com fome.", Palette.HUD_TEXTO)

func _process(delta: float) -> void:
	if _fade > 0.0:
		_fade = maxf(0.0, _fade - delta * 0.7)
		queue_redraw()

	if Input.is_action_just_pressed("reiniciar") and _morto:
		# 2: morte = reset total. Nada atravessa para a proxima run.
		GameState.reset_run()
		_semente = randi()
		_montar()
		return

	if _morto:
		return

	if Input.is_action_just_pressed("pausar"):
		_pausado = not _pausado
		get_tree().paused = _pausado
		queue_redraw()
	if _pausado:
		return

	GameState.tempo_run += delta

	_ciclo_de_spawn(delta)
	_procurar_interacoes()
	_ler_interacoes()

# ------------------------------------------------------------------ spawn
## 2: um monstro a cada 10s, em local aleatorio, respeitando o teto de vivos.
func _ciclo_de_spawn(delta: float) -> void:
	_t_spawn += delta
	if _t_spawn < Balance.SPAWN_INTERVALO:
		return
	_t_spawn = 0.0
	if monstros_vivos() >= GameState.teto_de_monstros():
		return
	_nascer_monstro(true)

func _nascer_monstro(anunciar: bool) -> void:
	# Escolhe entre as criaturas ja "liberadas": as mais duras entram
	# conforme os Cavaleiros vao caindo.
	var limite := mini(Balance.BESTIARIO.size(), 5 + GameState.cavaleiros_mortos * 2)
	var dados: Dictionary = Balance.BESTIARIO[_rng.randi_range(0, limite - 1)]

	var e := CENA_INIMIGO.new()
	e.configurar(dados, dungeon, jogador, _rng.randi())
	e.global_position = dungeon.chao_aleatorio(_rng, jogador.global_position, 260.0)
	e.morreu.connect(_ao_morrer_monstro)
	e.add_to_group("inimigos")
	$Atores.add_child(e)

	# brota do chao
	e.modulate.a = 0.0
	var y := e.global_position.y
	e.global_position.y = y + 16.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(e, "modulate:a", 1.0, 0.45)
	tw.tween_property(e, "global_position:y", y, 0.45).set_trans(Tween.TRANS_CUBIC)
	if anunciar:
		GameState.mensagem("Algo sobe pelo chão.", Palette.HUD_FRACO)

func monstros_vivos() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("inimigos"):
		if is_instance_valid(e) and not e.morto:
			n += 1
	for k in get_tree().get_nodes_in_group("cavaleiros"):
		if is_instance_valid(k) and not k.morto:
			n += 1      # 2: o teto inclui os mini-bosses
	return n

# -------------------------------------------------------- gatilho do mini-boss
func _ao_morrer_monstro(_e) -> void:
	# 2: 5 monstros em menos de 60s invocam um Cavaleiro.
	if GameState.registrar_morte_de_monstro():
		_invocar_cavaleiro()

func _invocar_cavaleiro() -> void:
	if GameState.minibosses_vivos >= 1 and GameState.cavaleiros_mortos == 0:
		return    # na demo, um Cavaleiro por vez
	var idx := mini(GameState.cavaleiros_mortos, Balance.CAVALEIROS.size() - 1)
	var dados := Balance.cavaleiro_por_indice(idx)

	var k := CENA_CAVALEIRO.new()
	k.configurar(dados, dungeon, jogador, _rng.randi())
	k.global_position = dungeon.chao_aleatorio(_rng, jogador.global_position, 300.0)
	k.morreu.connect(_ao_morrer_cavaleiro)
	k.add_to_group("cavaleiros")
	$Atores.add_child(k)
	GameState.minibosses_vivos += 1

	GameState.mensagem("Você matou rápido demais. %s vem cobrar." % String(dados["nome"]),
			Palette.SANGUE_VIVO)
	if GameState.resistencia < 100:
		# 5: a regra dura, dita na cara do jogador.
		GameState.mensagem("Resistência %d: os golpes dele te matam de um toque. Desvie."
				% GameState.resistencia, Palette.ALERTA)

func _ao_morrer_cavaleiro(k) -> void:
	GameState.minibosses_vivos = maxi(0, GameState.minibosses_vivos - 1)
	GameState.cavaleiros_mortos += 1
	GameState.mensagem("%s cai. 30 segundos para inspecionar o corpo."
			% String(k.dados["nome"]), Palette.HUD_DESTAQUE)

# ----------------------------------------------------------- interacoes
func _procurar_interacoes() -> void:
	_cadaver_perto = null
	_cavaleiro_perto = null
	var melhor := 56.0
	for e in get_tree().get_nodes_in_group("inimigos"):
		if not is_instance_valid(e) or not e.pode_consumir():
			continue
		var d: float = e.global_position.distance_to(jogador.global_position)
		if d < melhor:
			melhor = d
			_cadaver_perto = e
	var melhor_k := 80.0
	for k in get_tree().get_nodes_in_group("cavaleiros"):
		if not is_instance_valid(k) or not k.pode_inspecionar():
			continue
		var d: float = k.global_position.distance_to(jogador.global_position)
		if d < melhor_k:
			melhor_k = d
			_cavaleiro_perto = k
	queue_redraw()

func _ler_interacoes() -> void:
	if jogador.esta_desmaiado():
		return
	if Input.is_action_just_pressed("consumir") and _cadaver_perto != null:
		jogador.consumir(_cadaver_perto)
		_cadaver_perto = null
	if Input.is_action_just_pressed("interagir") and _cavaleiro_perto != null:
		_inspecionar(_cavaleiro_perto)

## 5: dentro dos 30s, a arma dropa 100%. Ela vai para a ALMA, nao para o
## inventario, entao nao custa slot nem peso.
func _inspecionar(k: Knight) -> void:
	k.arma_coletada = true
	var arma := String(k.dados["arma"])
	GameState.ganhar_arma(arma)
	GameState.mensagem("%s entra na sua alma. %s: %s" % [arma, String(k.dados["hab"]),
			String(k.dados["hab_desc"])], Palette.HUD_DESTAQUE)
	_cavaleiro_perto = null

# ------------------------------------------------------------------- morte
func _ao_morrer() -> void:
	if _morto:
		return
	_morto = true
	get_tree().paused = true
	hud.mostrar_morte(true)
	GameState.mensagem("O Submundo te engole.", Palette.SANGUE_VIVO)

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	# vinheta de entrada
	if _fade > 0.0:
		var r := get_viewport_rect().size * 4.0
		draw_rect(Rect2(-r * 0.5 + jogador.global_position, r), Color(0, 0, 0, _fade))

	# Prompts de interacao: nao explicam mecanica, so dizem que da pra agir.
	if _cadaver_perto != null and is_instance_valid(_cadaver_perto):
		_prompt(_cadaver_perto.global_position, "E  comer")
	if _cavaleiro_perto != null and is_instance_valid(_cavaleiro_perto):
		_prompt(_cavaleiro_perto.global_position,
				"F  inspecionar  (%ds)" % int(ceil(_cavaleiro_perto.janela_de_inspecao())))
	if _pausado:
		_tela_pausa()

func _prompt(pos: Vector2, txt: String) -> void:
	var f := ThemeDB.fallback_font
	var p := pos + Vector2(-30, -46)
	draw_string(f, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.8))
	draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.HUD_DESTAQUE)

func _tela_pausa() -> void:
	var f := ThemeDB.fallback_font
	var c := jogador.global_position
	var linhas := [
		"PAUSADO",
		"",
		"WASD / setas   mover",
		"mouse          mirar",
		"J / clique     atacar   (segurar = ataque forte)",
		"espaço         aparar",
		"shift / L      dash",
		"ctrl           correr",
		"C              agachar",
		"E              comer um corpo",
		"F              inspecionar um Cavaleiro",
		"Q              alternar arma",
		"Tab            status",
		"P              retomar",
	]
	var y := c.y - 150.0
	for l in linhas:
		draw_string(f, Vector2(c.x - 160, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1,
				17 if l == "PAUSADO" else 13,
				Palette.HUD_TEXTO if l == "PAUSADO" else Palette.HUD_FRACO)
		y += 20.0

# ------------------------------------------------------------------ inputs
## Mapear em codigo em vez de no project.godot: a serializacao de
## InputEvent no .godot e verbosa e quebra facil em merge.
func _registrar_inputs() -> void:
	var mapa_teclas := {
		"mover_cima":     [KEY_W, KEY_UP],
		"mover_baixo":    [KEY_S, KEY_DOWN],
		"mover_esq":      [KEY_A, KEY_LEFT],
		"mover_dir":      [KEY_D, KEY_RIGHT],
		"atacar":         [KEY_J],
		"parry":          [KEY_SPACE],
		"dash":           [KEY_SHIFT, KEY_L],
		"correr":         [KEY_CTRL],
		"agachar":        [KEY_C],
		"consumir":       [KEY_E],
		"interagir":      [KEY_F],
		"alternar_arma":  [KEY_Q],
		"status":         [KEY_TAB],
		"pausar":         [KEY_P],
		"reiniciar":      [KEY_R],
	}
	for acao in mapa_teclas:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao, 0.2)
		for k in mapa_teclas[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(acao, ev)

	var clique := InputEventMouseButton.new()
	clique.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("atacar", clique)
	var clique_dir := InputEventMouseButton.new()
	clique_dir.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("parry", clique_dir)
