class_name HUD
extends Control

## O HUD tem um trabalho central: deixar a RESISTENCIA e a faixa de parry
## visiveis o tempo todo. A mecanica do 7.3 e invisivel se o jogador nao
## souber em que degrau da tabela ele esta - e e ela que decide se aparar
## e uma jogada ou um suicidio.

var jogador: Player
var mundo: Node

var _linhas: Array = []          # log recente
const MAX_LINHAS := 5

var _fonte: Font
var _mostrar_status: bool = false
var _tela_morte: bool = false

func _ready() -> void:
	_fonte = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameState.log_novo.connect(_registrar)
	GameState.stats_mudaram.connect(queue_redraw)

func _registrar(texto: String, cor: Color) -> void:
	_linhas.append({"t": texto, "c": cor, "idade": 0.0})
	while _linhas.size() > MAX_LINHAS:
		_linhas.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	for l in _linhas:
		l["idade"] += delta
	while _linhas.size() > 0 and float(_linhas[0]["idade"]) > 6.0:
		_linhas.pop_front()
	_mostrar_status = Input.is_action_pressed("status") \
			or (jogador != null and is_instance_valid(jogador) and jogador.esta_desmaiado())
	queue_redraw()

func mostrar_morte(v: bool) -> void:
	_tela_morte = v
	queue_redraw()

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	var tela := get_viewport_rect().size

	_painel_esquerdo()
	_painel_direito(tela)
	_log(tela)

	# 2: o menu de status abre durante o desmaio - a unica coisa que voce
	# ainda consegue fazer enquanto o corpo rejeita o que voce comeu.
	if _mostrar_status:
		_menu_status(tela)
	if _tela_morte:
		_morte(tela)

func _txt(pos: Vector2, s: String, cor: Color, tam: int = 13) -> void:
	draw_string(_fonte, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam,
			Color(0, 0, 0, 0.75))
	draw_string(_fonte, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

func _barra(x: float, y: float, w: float, h: float, f: float, cor: Color) -> void:
	draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), Palette.CONTORNO)
	draw_rect(Rect2(x, y, w, h), Color(0.12, 0.10, 0.10))
	draw_rect(Rect2(x, y, w * clampf(f, 0.0, 1.0), h), cor)

func _painel_esquerdo() -> void:
	draw_rect(Rect2(8, 8, 236, 92), Palette.HUD_FUNDO)

	# vida
	_barra(16, 18, 200, 10, GameState.hp / GameState.hp_max, Palette.HUD_VIDA)
	_txt(Vector2(16, 42), "VIDA  %d/%d" % [int(ceil(GameState.hp)), int(GameState.hp_max)],
			Palette.HUD_TEXTO, 12)

	# 7.3: resistencia e a faixa de parry correspondente
	var r := GameState.resistencia
	_barra(16, 50, 200, 8, float(r) / 100.0, Palette.HUD_RESIST)
	var faixa := String(Balance.parry_result(r, 1.0)["nome"])
	var cor_faixa := Palette.HUD_RESIST if r >= 100 else Palette.HUD_DESTAQUE
	if r < 25:
		cor_faixa = Palette.ALERTA
	_txt(Vector2(16, 72), "RESIST %d  ·  %s" % [r, faixa], cor_faixa, 12)

	# 3.2: onde o jogador esta na curva de 51
	var c := GameState.consumos_total
	var ef := Balance.consume_effect(c)
	_txt(Vector2(16, 90), "CONSUMOS %d  (%s)" % [c, String(ef["faixa"])], Palette.HUD_FRACO, 11)

func _painel_direito(tela: Vector2) -> void:
	var x := tela.x - 244.0
	draw_rect(Rect2(x, 8, 236, 92), Palette.HUD_FUNDO)

	var vivos := 0
	if mundo != null and mundo.has_method("monstros_vivos"):
		vivos = mundo.monstros_vivos()
	_txt(Vector2(x + 10, 26), "MONSTROS %d/%d" % [vivos, GameState.teto_de_monstros()],
			Palette.HUD_TEXTO, 12)

	var arma := GameState.arma_equipada
	_txt(Vector2(x + 10, 44), "ARMA  " + (arma if arma != "" else "mãos nuas"),
			Palette.HUD_DESTAQUE if arma != "" else Palette.HUD_FRACO, 12)

	# 3.4: inventario e o peso que ele impoe
	var inv := "INVENTÁRIO  "
	for i in range(GameState.slots):
		inv += ("[%s]" % GameState.inventario[i]) if i < GameState.inventario.size() else "[ ]"
	_txt(Vector2(x + 10, 62), inv, Palette.HUD_FRACO, 11)

	if jogador != null and is_instance_valid(jogador) and jogador.combo > 1:
		_txt(Vector2(x + 10, 82), "COMBO x%d  (+%d%%)" % [jogador.combo,
				int(round(Balance.COMBO_GANHO * jogador.combo * 100.0))],
				Palette.HUD_DESTAQUE, 12)
	else:
		_txt(Vector2(x + 10, 82), "TEMPO %ds" % int(GameState.tempo_run), Palette.HUD_FRACO, 11)

func _log(tela: Vector2) -> void:
	var y := tela.y - 34.0
	for i in range(_linhas.size() - 1, -1, -1):
		var l = _linhas[i]
		var a := clampf(1.0 - (float(l["idade"]) - 4.0) / 2.0, 0.0, 1.0)
		var c: Color = l["c"]
		_txt(Vector2(16, y), String(l["t"]), Color(c.r, c.g, c.b, a), 13)
		y -= 17.0

# ------------------------------------------------------------ menu de status
func _menu_status(tela: Vector2) -> void:
	var w := 380.0
	var h := 268.0
	var x := (tela.x - w) * 0.5
	var y := (tela.y - h) * 0.5
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), Palette.CONTORNO)
	draw_rect(Rect2(x, y, w, h), Color(0.07, 0.06, 0.06, 0.95))

	var desmaiado := jogador != null and is_instance_valid(jogador) and jogador.esta_desmaiado()
	_txt(Vector2(x + 16, y + 26), "DESMAIADO" if desmaiado else "STATUS",
			Palette.ALERTA if desmaiado else Palette.HUD_TEXTO, 16)
	if desmaiado:
		_txt(Vector2(x + 16, y + 44), "o corpo ainda não aceita o que você comeu",
				Palette.HUD_FRACO, 11)

	var ly := y + 72.0
	_txt(Vector2(x + 16, ly), "RESISTÊNCIA %d" % GameState.resistencia, Palette.HUD_RESIST, 13)
	ly += 18.0
	_txt(Vector2(x + 16, ly), "parry: " + String(Balance.parry_result(GameState.resistencia, 1.0)["nome"]),
			Palette.HUD_FRACO, 11)
	ly += 24.0

	# 3.3: habilidades destravadas por consumo
	_txt(Vector2(x + 16, ly), "HABILIDADES", Palette.HUD_TEXTO, 13)
	ly += 18.0
	if GameState.habilidades.is_empty():
		_txt(Vector2(x + 24, ly), "nenhuma — você ainda não comeu nada", Palette.HUD_FRACO, 11)
		ly += 16.0
	else:
		for id in GameState.habilidades:
			var hab: Dictionary = GameState.habilidades[id]
			var n := int(hab["consumos"])
			var pct := int(round(Balance.habilidade_escala(n) * 100.0))
			var marca := " MAX" if n >= Balance.HAB_CONSUMOS_MAX else ""
			_txt(Vector2(x + 24, ly), "%s  (%s, %dx, %d%%)%s" % [String(hab["nome"]),
					String(hab["tipo"]), n, pct, marca],
					Palette.PUTRIDO if marca == "" else Palette.HUD_DESTAQUE, 11)
			ly += 15.0

	ly += 10.0
	# 7.6: proficiencia por acao
	_txt(Vector2(x + 16, ly), "PROFICIÊNCIA", Palette.HUD_TEXTO, 13)
	ly += 18.0
	if GameState.proficiencia.is_empty():
		_txt(Vector2(x + 24, ly), "nenhum golpe treinado", Palette.HUD_FRACO, 11)
	else:
		for acao in GameState.proficiencia:
			var usos := int(GameState.proficiencia[acao])
			var nv := Balance.proficiency_level(usos)
			_txt(Vector2(x + 24, ly), "%s  nv%d %s  (%d usos, +%d dano)" % [
					String(acao).replace("_", " "), nv, Balance.PROF_NOMES[nv - 1],
					usos, Balance.proficiency_bonus(usos)], Palette.HUD_FRACO, 11)
			ly += 15.0

	if GameState.armas_na_alma.size() > 0:
		ly += 10.0
		_txt(Vector2(x + 16, ly), "ARMAS NA ALMA", Palette.HUD_TEXTO, 13)
		ly += 18.0
		for a in GameState.armas_na_alma:
			_txt(Vector2(x + 24, ly), a, Palette.HUD_DESTAQUE, 11)
			ly += 15.0

# ------------------------------------------------------------------- morte
func _morte(tela: Vector2) -> void:
	draw_rect(Rect2(0, 0, tela.x, tela.y), Color(0.05, 0.01, 0.01, 0.82))
	var cx := tela.x * 0.5
	var cy := tela.y * 0.5
	draw_string(_fonte, Vector2(cx - 120, cy - 40), "VOCÊ MORREU",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Palette.SANGUE_VIVO)
	# 2: morrer reseta TUDO - consumos e inventario inclusive.
	var n := GameState.consumos_total
	var quantos := ("o único consumo" if n == 1 else "os %d consumos" % n)
	draw_string(_fonte, Vector2(cx - 210, cy - 4),
			"a adaptação se perde. %s, o inventário, as armas." % quantos,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.HUD_FRACO)
	draw_string(_fonte, Vector2(cx - 210, cy + 18),
			"monstros mortos nesta run: %d" % GameState.monstros_mortos,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.HUD_FRACO)
	draw_string(_fonte, Vector2(cx - 100, cy + 58), "R  —  acordar de novo",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.HUD_TEXTO)
