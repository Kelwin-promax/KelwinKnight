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

var _hitstop: int = 0
var _shake_forca: float = 0.0
var _particulas: Array = []
var _ambiente: Array = []
var _t_ambiente: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_registrar_inputs()
	randomize()
	_semente = randi()
	GameState.impacto.connect(_ao_impacto)
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

	_criar_iluminacao()

	capa = CanvasLayer.new()
	add_child(capa)
	hud = HUD.new()
	hud.jogador = jogador
	hud.mundo = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	capa.add_child(hud)

	# Populacao inicial: o mapa ja comeca no limite atual de monstros vivos.
	for i in range(GameState.teto_de_monstros()):
		_nascer_monstro(false)

	_t_spawn = 0.0
	_morto = false
	_fade = 1.0
	_hitstop = 0
	_shake_forca = 0.0
	_particulas.clear()
	_ambiente.clear()
	_t_ambiente = 0.0
	Engine.time_scale = 1.0
	hud.mostrar_morte(false)
	GameState.mensagem("Você acorda com fome.", Palette.HUD_TEXTO)

func _process(delta: float) -> void:
	if _hitstop > 0:
		_hitstop -= 1
		Engine.time_scale = 0.05
	elif Engine.time_scale < 1.0 and not _pausado and not _morto:
		Engine.time_scale = 1.0

	_aplicar_shake()
	_atualizar_particulas(delta)
	_atualizar_ambiente(delta)

	if _fade > 0.0:
		_fade = maxf(0.0, _fade - delta * 0.7)
		queue_redraw()

	if Input.is_action_just_pressed("reiniciar") and _morto:
		Engine.time_scale = 1.0
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

# --------------------------------------------------------------- impacto
func _ao_impacto(forca: float, pos: Vector2, dir: Vector2) -> void:
	_hitstop = maxi(_hitstop, int(2.0 + forca * 4.0))
	_shake_forca = maxf(_shake_forca, 2.0 + forca * 10.0)
	var n := int(3.0 + forca * 6.0)
	for i in range(n):
		var ang := dir.angle() + randf_range(-0.9, 0.9)
		var spd := randf_range(50.0, 160.0) * (0.6 + forca)
		_particulas.append({
			"p": Vector2(pos),
			"v": Vector2(cos(ang), sin(ang)) * spd,
			"t": randf_range(0.25, 0.55),
			"c": Color(Palette.SANGUE.r + randf_range(0.0, 0.12),
					Palette.SANGUE.g, Palette.SANGUE.b),
			"r": randf_range(1.5, 3.0 + forca * 2.0),
		})
	queue_redraw()

func _aplicar_shake() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if _shake_forca > 0.3:
		camera.offset = Vector2(
			randf_range(-_shake_forca, _shake_forca),
			randf_range(-_shake_forca, _shake_forca))
		_shake_forca *= 0.78
	else:
		_shake_forca = 0.0
		camera.offset = Vector2.ZERO

func _atualizar_particulas(delta: float) -> void:
	var i := _particulas.size() - 1
	while i >= 0:
		var p: Dictionary = _particulas[i]
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) <= 0.0:
			_particulas.remove_at(i)
		else:
			p["p"] = Vector2(p["p"]) + Vector2(p["v"]) * delta
			p["v"] = Vector2(p["v"]) * 0.90
		i -= 1
	if not _particulas.is_empty():
		queue_redraw()

func _atualizar_ambiente(delta: float) -> void:
	if jogador == null or not is_instance_valid(jogador):
		return
	_t_ambiente += delta
	if _t_ambiente >= 0.15 and _ambiente.size() < 40:
		_t_ambiente = 0.0
		var ang := randf() * TAU
		var dist := randf_range(40.0, 320.0)
		var p := jogador.global_position + Vector2(cos(ang), sin(ang)) * dist
		var tipo := randi() % 3
		if tipo == 0:
			_ambiente.append({
				"p": Vector2(p), "v": Vector2(randf_range(-8, 8), randf_range(-18, -6)),
				"t": randf_range(2.5, 5.0), "c": Color(1.0, 0.5, 0.15, 0.0),
				"r": randf_range(1.0, 2.0), "fade_in": 0.6,
			})
		elif tipo == 1:
			_ambiente.append({
				"p": Vector2(p), "v": Vector2(randf_range(-5, 5), randf_range(-3, 3)),
				"t": randf_range(3.0, 6.0), "c": Color(0.4, 0.3, 0.25, 0.0),
				"r": randf_range(0.8, 1.5), "fade_in": 1.0,
			})
		else:
			_ambiente.append({
				"p": Vector2(p), "v": Vector2(randf_range(-4, 4), randf_range(-12, -4)),
				"t": randf_range(2.0, 4.0), "c": Color(0.7, 0.15, 0.1, 0.0),
				"r": randf_range(0.6, 1.2), "fade_in": 0.5,
			})
	var i := _ambiente.size() - 1
	while i >= 0:
		var a: Dictionary = _ambiente[i]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			_ambiente.remove_at(i)
		else:
			a["p"] = Vector2(a["p"]) + Vector2(a["v"]) * delta
			a["fade_in"] = maxf(0.0, float(a["fade_in"]) - delta)
		i -= 1
	if not _ambiente.is_empty():
		queue_redraw()

# -------------------------------------------------------------- iluminacao
func _criar_iluminacao() -> void:
	var escurece := CanvasModulate.new()
	escurece.color = Color(0.06, 0.04, 0.06)
	add_child(escurece)

	var tex := _gradiente_luz(256)
	var luz := PointLight2D.new()
	luz.texture = tex
	luz.texture_scale = 5.0
	luz.energy = 1.0
	luz.color = Color(1.0, 0.92, 0.85)
	jogador.add_child(luz)

	var tex_peq := _gradiente_luz(64)
	for pos in mapa._deco:
		var d: Vector2i = mapa._deco[pos]
		if d == MapaVisual.DECO_LAVA_CORE:
			var lz := PointLight2D.new()
			lz.texture = tex_peq
			lz.texture_scale = 4.0
			lz.energy = 0.5
			lz.color = Color(1.0, 0.45, 0.15)
			lz.position = Vector2(
				float(pos.x) * float(Dungeon.TILE) + float(Dungeon.TILE) * 0.5,
				float(pos.y) * float(Dungeon.TILE) + float(Dungeon.TILE) * 0.5)
			mapa.add_child(lz)
		elif d == MapaVisual.DECO_ALTAR:
			var lz := PointLight2D.new()
			lz.texture = tex_peq
			lz.texture_scale = 3.0
			lz.energy = 0.35
			lz.color = Color(1.0, 0.6, 0.3)
			lz.position = Vector2(
				float(pos.x) * float(Dungeon.TILE) + float(Dungeon.TILE) * 0.5,
				float(pos.y) * float(Dungeon.TILE) + float(Dungeon.TILE) * 0.5)
			mapa.add_child(lz)

func _gradiente_luz(tamanho: int) -> ImageTexture:
	var img := Image.create(tamanho, tamanho, false, Image.FORMAT_RGBA8)
	var centro := float(tamanho) * 0.5
	for ix in range(tamanho):
		for iy in range(tamanho):
			var d := Vector2(float(ix) - centro, float(iy) - centro).length() / centro
			var a := clampf(1.0 - d * d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(a, a, a, a))
	return ImageTexture.create_from_image(img)

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

func _ponto_spawn_monstro() -> Vector2:
	# Torna a zona de spawn mais agressiva perto do jogador, sem mexer no teto
	# global de 30 monstros. O objetivo e que o jogador veja inimigos no caminho
	# em vez de andar muito sem contato.
	for i in range(200):
		var ang := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(80.0, 260.0)
		var p := jogador.global_position + Vector2(cos(ang), sin(ang)) * dist
		if dungeon.solido_em(p):
			continue
		if p.distance_to(jogador.global_position) < 60.0:
			continue
		return p
	return dungeon.chao_aleatorio(_rng, jogador.global_position, 50.0)

func _nascer_monstro(anunciar: bool) -> void:
	# Escolhe entre as criaturas ja "liberadas": as mais duras entram
	# conforme os Cavaleiros vao caindo.
	var limite := mini(Balance.BESTIARIO.size(), 5 + GameState.cavaleiros_mortos * 2)
	var dados: Dictionary = Balance.BESTIARIO[_rng.randi_range(0, limite - 1)]

	var e := CENA_INIMIGO.new()
	e.configurar(dados, dungeon, jogador, _rng.randi())
	e.global_position = _ponto_spawn_monstro()
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
	Engine.time_scale = 1.0
	_hitstop = 0
	get_tree().paused = true
	hud.mostrar_morte(true)
	GameState.mensagem("O Submundo te engole.", Palette.SANGUE_VIVO)

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	for part in _particulas:
		var a := clampf(float(part["t"]) * 3.0, 0.0, 1.0)
		var c: Color = part["c"]
		draw_circle(Vector2(part["p"]), float(part["r"]),
				Color(c.r, c.g, c.b, a * 0.85))

	for amb in _ambiente:
		var fi := float(amb["fade_in"])
		var vis := clampf(1.0 - fi, 0.0, 1.0) * clampf(float(amb["t"]) * 2.0, 0.0, 1.0)
		var c: Color = amb["c"]
		draw_circle(Vector2(amb["p"]), float(amb["r"]),
				Color(c.r, c.g, c.b, vis * 0.45))

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
