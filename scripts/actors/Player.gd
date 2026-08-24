class_name Player
extends Node2D

## 7: combate em tempo real. Socos em combo (jab, direto, cruzado, uppercut),
## chutes em combo (chute, chute alto, chute giratorio), golpes pesados
## direcionais (cabecada, joelhada, cotovelada), dash, pulo, parry.

signal morreu()
signal desmaiou(duracao: float)
signal acao_relevante(texto: String, cor: Color)

const RAIO := 9.0
const ACEL := 1500.0
const VEL_MAX := 168.0
const ATRITO := 1400.0

var dungeon: Dungeon
var mira: Vector2 = Vector2.RIGHT
var vel: Vector2 = Vector2.ZERO
var _t: float = 0.0

# --- dash (7.2)
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _invuln: float = 0.0

# --- pulo
var _pulo_t: float = 0.0
var _pulo_cd: float = 0.0

# --- ataque
var _atk_t: float = -1.0
var _atk_id: String = ""
var _atk_acertou: bool = false
var _atk_dados: Dictionary = Balance.ATK_JAB
var _carga: float = -1.0

# --- combo de socos
var _combo_soco: int = 0
var _combo_soco_t: float = 0.0

# --- combo de chutes
var _combo_chute: int = 0
var _combo_chute_t: float = 0.0

# --- parry (7.3)
var _parry_t: float = -1.0
var _parry_absorveu: bool = false
var _vuln: float = 0.0
var _caido: float = 0.0

# --- combo e especializacao (7.5)
var combo: int = 0
var _combo_t: float = 0.0
var _ultima_acao: String = ""
var _repeticoes: int = 0
var _impeto: int = 0

# --- critico garantido do contra-ataque de parry (7.3)
var _crit_contra: Node = null
var _crit_t: float = 0.0

# --- rastro do dash
var _rastro: Array[Vector2] = []

# --- estados de corpo
var _desmaio: float = 0.0
var _lentidao: float = 0.0
var _agachado: bool = false
var _mouse_t: float = 99.0
var _flash: float = 0.0
var _vomito: float = 0.0

func configurar(p_dungeon: Dungeon) -> void:
	dungeon = p_dungeon

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_t = 0.0

func _process(delta: float) -> void:
	_t += delta
	_mouse_t += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	_vomito = maxf(0.0, _vomito - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_pulo_cd = maxf(0.0, _pulo_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_vuln = maxf(0.0, _vuln - delta)
	_caido = maxf(0.0, _caido - delta)
	_crit_t = maxf(0.0, _crit_t - delta)
	if _crit_t <= 0.0:
		_crit_contra = null

	if _desmaio > 0.0:
		_desmaio -= delta
		vel = vel.lerp(Vector2.ZERO, delta * 5.0)
		_mover(delta)
		queue_redraw()
		return

	_atualizar_combos(delta)
	_atualizar_parry(delta)
	_atualizar_ataque(delta)
	_atualizar_pulo(delta)

	if _pode_agir():
		_ler_movimento(delta)
		_ler_acoes(delta)
	else:
		vel = vel.lerp(Vector2.ZERO, delta * 6.0)

	_atualizar_dash(delta)
	_mover(delta)
	if _dash_t > 0.0:
		_rastro.append(global_position)
		while _rastro.size() > 4:
			_rastro.pop_front()
	else:
		_rastro.clear()
	queue_redraw()

func _pode_agir() -> bool:
	return _vuln <= 0.0 and _caido <= 0.0 and _desmaio <= 0.0

# ---------------------------------------------------------------- movimento
func _ler_movimento(delta: float) -> void:
	if _dash_t > 0.0 or _pulo_t > 0.0:
		return
	var dir := Vector2(
		Input.get_axis("mover_esq", "mover_dir"),
		Input.get_axis("mover_cima", "mover_baixo"))
	if dir.length() > 1.0:
		dir = dir.normalized()

	_agachado = Input.is_action_pressed("agachar")

	var teto := VEL_MAX
	if Input.is_action_pressed("correr") and not _agachado:
		teto *= Balance.CORRIDA_MULT
	if _agachado:
		teto *= 0.45
	teto *= (1.0 - _lentidao)
	teto *= GameState.penalidade_de_peso()
	if _atk_t >= 0.0:
		teto *= 0.25

	if dir.length() > 0.01:
		vel = vel.move_toward(dir * teto, ACEL * delta)
	else:
		vel = vel.move_toward(Vector2.ZERO, ATRITO * delta)

	var mouse_recente := _mouse_t < 1.5
	if mouse_recente:
		var para_mouse := get_global_mouse_position() - global_position
		if para_mouse.length() > 26.0:
			mira = para_mouse.normalized()
		elif dir.length() > 0.01:
			mira = dir.normalized()
	elif dir.length() > 0.01:
		mira = dir.normalized()

func _mover(delta: float) -> void:
	if vel.length() < 0.01:
		return
	global_position = dungeon.mover(global_position, vel * delta, RAIO)

# -------------------------------------------------------------------- dash
func _atualizar_dash(delta: float) -> void:
	if _dash_t > 0.0:
		_dash_t -= delta
		vel = _dash_dir * Balance.DASH_VEL
		if _dash_t <= 0.0:
			vel = _dash_dir * VEL_MAX * 0.6

func _tentar_dash() -> void:
	if _dash_cd > 0.0 or _dash_t > 0.0:
		return
	var dir := Vector2(
		Input.get_axis("mover_esq", "mover_dir"),
		Input.get_axis("mover_cima", "mover_baixo"))
	_dash_dir = dir.normalized() if dir.length() > 0.01 else mira
	_dash_t = Balance.DASH_DUR
	_dash_cd = Balance.DASH_CD
	_invuln = Balance.DASH_INVULN
	GameState.registrar_uso("dash")

# --------------------------------------------------------------------- pulo
func _tentar_pular() -> void:
	if _pulo_cd > 0.0 or _pulo_t > 0.0 or _dash_t > 0.0:
		return
	_pulo_t = Balance.PULO_DURACAO
	_pulo_cd = Balance.PULO_CD + Balance.PULO_DURACAO
	_invuln = Balance.PULO_INVULN
	GameState.registrar_uso("pulo")

func _atualizar_pulo(delta: float) -> void:
	_pulo_t = maxf(0.0, _pulo_t - delta)

# ------------------------------------------------------------------- acoes
func _ler_acoes(delta: float) -> void:
	if Input.is_action_just_pressed("dash"):
		_tentar_dash()

	if Input.is_action_just_pressed("pular"):
		_tentar_pular()

	if Input.is_action_just_pressed("parry"):
		_iniciar_parry()

	# socos: segurar carrega golpe pesado, soltar rapido faz combo de socos
	if Input.is_action_pressed("atacar"):
		if _carga < 0.0:
			_carga = 0.0
		else:
			_carga += delta
	elif _carga >= 0.0:
		var pesado := _carga >= Balance.CARGA_MIN
		_carga = -1.0
		if _atk_t < 0.0:
			if pesado:
				_iniciar_golpe_pesado()
			else:
				_iniciar_soco()

	# chutes: botao dedicado com combo chain
	if Input.is_action_just_pressed("chutar"):
		if _atk_t < 0.0:
			_iniciar_chute()

	if Input.is_action_just_pressed("alternar_arma"):
		GameState.alternar_arma()
		var nome := GameState.arma_equipada
		acao_relevante.emit("Empunha: " + (nome if nome != "" else "as próprias mãos"), Palette.HUD_DESTAQUE)

# ------------------------------------------------------------------ ataques
func _iniciar_soco() -> void:
	if _combo_soco_t > 0.0 and _combo_soco < Balance.COMBO_SOCOS.size() - 1:
		_combo_soco += 1
	else:
		_combo_soco = 0
	_atk_dados = Balance.COMBO_SOCOS[_combo_soco]
	_atk_id = String(_atk_dados["id"])
	_atk_t = 0.0
	_atk_acertou = false
	_combo_soco_t = 0.0

func _iniciar_chute() -> void:
	if _combo_chute_t > 0.0 and _combo_chute < Balance.COMBO_CHUTES.size() - 1:
		_combo_chute += 1
	else:
		_combo_chute = 0
	_atk_dados = Balance.COMBO_CHUTES[_combo_chute]
	_atk_id = String(_atk_dados["id"])
	_atk_t = 0.0
	_atk_acertou = false
	_combo_chute_t = 0.0

func _iniciar_golpe_pesado() -> void:
	var dir := Vector2(
		Input.get_axis("mover_esq", "mover_dir"),
		Input.get_axis("mover_cima", "mover_baixo"))
	var movendo_frente := dir.length() > 0.3 and dir.normalized().dot(mira) > 0.3
	_atk_dados = Balance.golpe_pesado(_agachado, movendo_frente)
	_atk_id = String(_atk_dados["id"])
	_atk_t = 0.0
	_atk_acertou = false

func _atk_eh_pesado() -> bool:
	return _atk_id in ["uppercut", "chute_alto", "chute_giro", "cabecada", "joelhada", "cotovelada"]

func _atualizar_ataque(delta: float) -> void:
	if _atk_t < 0.0:
		return
	_atk_t += delta
	var windup: float = _atk_dados["windup"]
	if _atk_t >= windup and not _atk_acertou:
		_atk_acertou = true
		_resolver_golpe()
	if _atk_t >= windup + float(_atk_dados["recup"]):
		# ao terminar, abre a janela de combo para o proximo input
		if _atk_id in ["jab", "direto", "cruzado", "uppercut"]:
			_combo_soco_t = Balance.COMBO_INPUT_JANELA
		elif _atk_id in ["chute", "chute_alto", "chute_giro"]:
			_combo_chute_t = Balance.COMBO_INPUT_JANELA
		_atk_t = -1.0

func _resolver_golpe() -> void:
	var alcance: float = _atk_dados["alcance"]
	var arco: float = _atk_dados["arco"]
	var kb: float = float(_atk_dados.get("kb", 70.0))
	var acertou_algo := false

	var candidatos := get_tree().get_nodes_in_group("inimigos")
	candidatos.append_array(get_tree().get_nodes_in_group("cavaleiros"))
	for e in candidatos:
		if not is_instance_valid(e) or e.morto:
			continue
		var d: Vector2 = e.global_position - global_position
		var dist := d.length()
		if dist > alcance + e.raio:
			continue
		if absf(mira.angle_to(d.normalized())) > arco * 0.5:
			continue

		var dano := _calcular_dano(e)
		e.levar_dano(dano["valor"], d.normalized() * kb)
		acertou_algo = true
		var fi: float = float(_atk_dados.get("impacto", 0.25))
		if String(dano["tipo"]) != "":
			fi = 0.8
		GameState.impacto.emit(fi, e.global_position, d.normalized())
		if String(dano["tipo"]) != "":
			acao_relevante.emit(dano["tipo"], Palette.HUD_DESTAQUE)

	var acao := GameState.acao_de_ataque(_atk_id)
	if acertou_algo:
		combo += 1
		_combo_t = Balance.COMBO_JANELA
		if acao == _ultima_acao:
			_repeticoes += 1
		else:
			_repeticoes = 0
			_ultima_acao = acao
		if GameState.arma_equipada == "Espada Colossal":
			_impeto += 1
		if GameState.registrar_uso(acao):
			var nv := GameState.nivel_proficiencia(acao)
			acao_relevante.emit("%s: nivel %d (%s)" % [acao.replace("_", " "), nv,
					Balance.PROF_NOMES[nv - 1]], Palette.HUD_RESIST)
	else:
		_impeto = 0

func _calcular_dano(inimigo: Node) -> Dictionary:
	var acao := GameState.acao_de_ataque(_atk_id)
	var base: float = _atk_dados["dano"]
	if GameState.arma_equipada == "Espada Colossal":
		base += 8.0

	base += float(GameState.bonus_proficiencia(acao))
	base *= Balance.damage_multiplier(combo, _repeticoes)
	if GameState.arma_equipada == "Espada Colossal":
		base *= Balance.impeto_belicoso(_impeto)

	var tipo := ""
	if inimigo.has_method("esta_de_costas_para") and inimigo.esta_de_costas_para(global_position) \
			and not inimigo.alertado():
		base *= Balance.BACKSTAB_MULT
		inimigo.atordoar(0.7)
		tipo = "FURTIVO ×2"
	elif _crit_contra == inimigo and _crit_t > 0.0:
		base *= Balance.CRIT_MULT
		_crit_contra = null
		tipo = "CONTRA-ATAQUE ×2"

	return {"valor": base, "tipo": tipo}

func _atualizar_combos(delta: float) -> void:
	# combo de dano (7.5)
	if combo > 0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			combo = 0
			_repeticoes = 0
	# janela de input dos combos de soco e chute
	if _combo_soco_t > 0.0:
		_combo_soco_t -= delta
		if _combo_soco_t <= 0.0:
			_combo_soco = 0
	if _combo_chute_t > 0.0:
		_combo_chute_t -= delta
		if _combo_chute_t <= 0.0:
			_combo_chute = 0

# ------------------------------------------------------------------- parry
func _iniciar_parry() -> void:
	if _parry_t >= 0.0:
		return
	_parry_t = 0.0
	_parry_absorveu = false
	GameState.registrar_uso("parry")

func _atualizar_parry(delta: float) -> void:
	if _parry_t < 0.0:
		return
	_parry_t += delta
	if _parry_t >= Balance.PARRY_WINDOW:
		if not _parry_absorveu:
			_vuln = maxf(_vuln, Balance.PARRY_FAIL_VULN)
			acao_relevante.emit("Parry no vazio", Palette.HUD_FRACO)
		_parry_t = -1.0

func parry_ativo() -> bool:
	return _parry_t >= 0.0 and _parry_t < Balance.PARRY_WINDOW

# -------------------------------------------------------------------- dano
func receber_golpe(dano: float, origem: Vector2, atacante: Node) -> Dictionary:
	if _invuln > 0.0:
		acao_relevante.emit("Esquiva", Palette.HUD_FRACO)
		return {"parry": false, "atordoa": false, "esquivou": true}

	if parry_ativo():
		_parry_absorveu = true
		_parry_t = -1.0
		var r := Balance.parry_result(GameState.resistencia, dano)
		var sofrido := float(r["dano"])
		if sofrido > 0.0:
			_aplicar_dano(sofrido, origem)
		if bool(r["critico"]):
			_crit_contra = atacante
			_crit_t = 1.4
		if float(r["vulneravel"]) > 0.0:
			_vuln = maxf(_vuln, float(r["vulneravel"]))
		if bool(r["queda"]):
			_caido = 1.1
		var cor := Palette.HUD_RESIST if sofrido <= 0.0 else Palette.HUD_DESTAQUE
		var etiqueta := String(r["nome"])
		if sofrido > 0.0:
			etiqueta += " (-%d)" % int(round(sofrido))
		acao_relevante.emit(etiqueta, cor)
		var dir_p := (global_position - origem)
		if dir_p.length() > 0.001:
			dir_p = dir_p.normalized()
		GameState.impacto.emit(0.6 if sofrido <= 0.0 else 0.35, global_position, dir_p)
		return {"parry": true, "atordoa": bool(r["atordoa"])}

	_aplicar_dano(dano, origem)
	var dir_d := (global_position - origem)
	if dir_d.length() > 0.001:
		dir_d = dir_d.normalized()
	GameState.impacto.emit(0.2, global_position, dir_d)
	return {"parry": false, "atordoa": false}

func _aplicar_dano(quanto: float, origem: Vector2) -> void:
	GameState.hp -= quanto
	GameState.stats_mudaram.emit()
	_flash = 1.0
	combo = 0
	_repeticoes = 0
	_impeto = 0
	var empurrao := (global_position - origem)
	if empurrao.length() > 0.001:
		vel += empurrao.normalized() * 130.0
	if GameState.hp <= 0.0:
		GameState.hp = 0.0
		morreu.emit()

# ------------------------------------------------------------------ consumo
func consumir(inimigo: Node) -> void:
	if not inimigo.pode_consumir():
		return
	inimigo.consumido = true
	var efeito := GameState.consumir(String(inimigo.dados["id"]))

	if bool(efeito["primeira_vez"]):
		acao_relevante.emit("Habilidade: " + String(efeito["habilidade"]), Palette.PUTRIDO)
	elif int(efeito["consumos_criatura"]) >= Balance.HAB_CONSUMOS_MAX:
		acao_relevante.emit(String(efeito["habilidade"]) + " no maximo", Palette.PUTRIDO)

	if int(efeito["hp"]) > 0:
		_flash = 1.0
		acao_relevante.emit("O corpo rejeita (-%d)" % int(efeito["hp"]), Palette.HUD_VIDA)
	if bool(efeito["vomito"]):
		_vomito = 1.2
	if float(efeito["lentidao"]) > 0.0:
		_lentidao = float(efeito["lentidao"])
		get_tree().create_timer(6.0).timeout.connect(func(): _lentidao = 0.0)
	if bool(efeito["desmaio"]):
		_desmaio = 3.0
		desmaiou.emit(_desmaio)
	if GameState.hp <= 0.0:
		morreu.emit()

func esta_desmaiado() -> bool:
	return _desmaio > 0.0

func esta_escondido() -> bool:
	return _agachado

# ------------------------------------------------------------------ desenho
func _anim_atual() -> Array:
	if _caido > 0.0 or _desmaio > 0.0:
		return ["caido", 0.0]
	if _vuln > 0.0:
		return ["dano", 0.0]
	if _parry_t >= 0.0 and _parry_t <= Balance.PARRY_WINDOW * 2.0:
		return ["parry", 0.0]
	if _pulo_t > 0.0:
		# os 3 quadros do pulo andam pelo progresso, nao pelo relogio: agacha,
		# sobe, fica no ar. Com fps fixo o salto inteiro (0.35s) acabaria antes
		# de a folha chegar no ultimo quadro.
		return ["pulo", 1.0 - _pulo_t / Balance.PULO_DURACAO]
	if _dash_t > 0.0:
		return ["dash", 0.0]
	if _atk_t >= 0.0:
		# quem decide o quadro e a folha, nao um progresso linear: cada golpe
		# marca em que quadro o punho chega, e e nele que o dano sai.
		return [_atk_id, SpriteJogador.progresso_de_ataque(_atk_id, _atk_t,
				float(_atk_dados["windup"]), float(_atk_dados["recup"]))]
	var v := vel.length()
	if v > VEL_MAX * 1.12:
		return ["correr", 0.0]
	if v > 12.0:
		return ["andar", 0.0]
	return ["parado", 0.0]

func _draw() -> void:
	for i in range(_rastro.size()):
		var a := 0.18 * (float(i + 1) / maxf(float(_rastro.size()), 1.0))
		var ofs := _rastro[i] - global_position
		draw_circle(ofs + Vector2(0, -14), 10.0,
				Color(Palette.TRAPO.r, Palette.TRAPO.g, Palette.TRAPO.b, a))

	var andando := vel.length() > 12.0
	var fase := 0.0
	if _atk_t >= 0.0:
		var w: float = _atk_dados["windup"]
		if _atk_t < w:
			fase = 0.02
		else:
			fase = clampf((_atk_t - w) / maxf(0.001, float(_atk_dados["recup"])), 0.0, 1.0)

	var lado := signf(mira.x) if absf(mira.x) > 0.05 else 1.0
	var rot := 1.2 if _caido > 0.0 else 0.0
	var desloc := Vector2(0, 6) if _caido > 0.0 else Vector2.ZERO
	# pulo: desloca o sprite pra cima
	if _pulo_t > 0.0:
		var fase_pulo := 1.0 - absf(2.0 * _pulo_t / Balance.PULO_DURACAO - 1.0)
		desloc += Vector2(0, -20.0 * fase_pulo)
	var an := _anim_atual()

	if SpriteJogador.disponivel():
		Figura.sombra(self, RAIO)
		SpriteJogador.desenhar(self, String(an[0]), _t, float(an[1]), lado, rot, desloc)
	else:
		if _caido > 0.0:
			draw_set_transform(desloc, rot, Vector2.ONE)
		Figura.jogador(self, mira, _t, andando, fase, _atk_eh_pesado(), parry_ativo(),
				GameState.arma_equipada)
		if _caido > 0.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# carga do ataque forte
	if _carga >= Balance.CARGA_MIN:
		draw_arc(Vector2(0, -18), 22.0, -PI * 0.5, -PI * 0.5 + TAU * minf(_carga / 0.9, 1.0),
				20, Palette.HUD_DESTAQUE, 2.5)

	if _invuln > 0.0:
		draw_arc(Vector2(0, -14), 19.0, 0.0, TAU, 24, Color(0.7, 0.8, 1.0, 0.5), 2.0)
	if _vuln > 0.0:
		draw_arc(Vector2(0, -14), 19.0, 0.0, TAU, 24, Color(Palette.ALERTA.r, Palette.ALERTA.g,
				Palette.ALERTA.b, 0.45), 2.0)
	if _flash > 0.0:
		draw_circle(Vector2(0, -14), 22.0, Color(1, 0.3, 0.3, 0.30 * _flash))
	if _vomito > 0.0:
		for i in range(5):
			var a := mira.angle() + (float(i) - 2.0) * 0.24
			var d := 14.0 + 20.0 * (1.2 - _vomito)
			draw_circle(Vector2(cos(a), sin(a)) * d + Vector2(0, -10), 3.0,
					Color(Palette.SANGUE.r, Palette.SANGUE.g, Palette.SANGUE.b, _vomito * 0.8))
	if combo > 1:
		draw_arc(Vector2(0, -14), 24.0, -PI * 0.5,
				-PI * 0.5 + TAU * minf(float(combo) / 10.0, 1.0), 22,
				Color(Palette.HUD_DESTAQUE.r, Palette.HUD_DESTAQUE.g, Palette.HUD_DESTAQUE.b, 0.55), 2.0)
