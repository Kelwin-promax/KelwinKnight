class_name Knight
extends Node2D

## 5: Cavaleiro do Apocalipse. Na demo, o primeiro - Guerra, 120 HP,
## Espada Colossal.
##
## A regra dura do documento: TODO golpe de Cavaleiro e mortal se a
## resistencia do jogador for menor que 100. Isso esta implementado ao pe da
## letra, e muda o jogo de lugar: com resistencia baixa nao existe aparar um
## Cavaleiro (25% de um golpe letal ainda e letal). A unica resposta e o dash,
## que da invencibilidade independente de resistencia (7.2). Aparar so vira
## opcao depois de ~50 consumos, que e exatamente onde a curva do 3.2 termina.

signal morreu(cavaleiro)

enum { ENTRADA, PERSEGUE, GOLPE, INVESTIDA, RECUPERA }

var dados: Dictionary
var dungeon: Dungeon
var alvo: Node2D

var hp: float
var hp_max: float
var raio: float = 20.0
var mira: Vector2 = Vector2.RIGHT
var vel: Vector2 = Vector2.ZERO

var estado: int = ENTRADA
var _t: float = 0.0
var _t_estado: float = 0.0
var _flash: float = 0.0
var _cd_autoridade: float = 0.0
var _acertou_no_padrao: bool = false
var _dir_investida: Vector2 = Vector2.RIGHT

var morto: bool = false
var _t_morte: float = 0.0
var arma_coletada: bool = false

const VEL := 118.0
const ALCANCE_GOLPE := 96.0
const TELEGRAFO_GOLPE := 0.90    # generoso de proposito: da pra ler e sair
const DURACAO_GOLPE := 0.30
const TELEGRAFO_INVESTIDA := 0.85
const DURACAO_INVESTIDA := 0.55
const VEL_INVESTIDA := 460.0
const CD_AUTORIDADE := 3.5

var rng := RandomNumberGenerator.new()

func configurar(p_dados: Dictionary, p_dungeon: Dungeon, p_alvo: Node2D, p_semente: int) -> void:
	dados = p_dados
	dungeon = p_dungeon
	alvo = p_alvo
	rng.seed = p_semente
	hp_max = float(dados["hp"])
	hp = hp_max

## 5: mortal com resistencia < 100. Acima disso o golpe e pesado, mas humano.
func dano_do_golpe() -> float:
	if GameState.resistencia < 100:
		return 9999.0
	return 34.0

func _process(delta: float) -> void:
	_t += delta
	_t_estado += delta
	_flash = maxf(0.0, _flash - delta * 3.0)

	if morto:
		_t_morte += delta
		queue_redraw()
		return

	_autoridade(delta)

	match estado:
		ENTRADA:
			vel = vel.lerp(Vector2.ZERO, delta * 4.0)
			if _t_estado > 1.4:
				_mudar(PERSEGUE)
		PERSEGUE:
			_encarar(alvo.global_position, delta * 4.0)
			var d := alvo.global_position - global_position
			if d.length() > 0.001:
				vel = vel.lerp(d.normalized() * VEL, delta * 4.0)
			if _t_estado > 0.7:
				if d.length() <= ALCANCE_GOLPE * 0.8:
					_mudar(GOLPE)
				elif d.length() < 620.0 and rng.randf() < 0.9:
					_mudar(INVESTIDA)
		GOLPE:
			_processar_golpe(delta)
		INVESTIDA:
			_processar_investida(delta)
		RECUPERA:
			vel = vel.lerp(Vector2.ZERO, delta * 5.0)
			if _t_estado > 0.75:
				_mudar(PERSEGUE)

	_mover(delta)
	queue_redraw()

func _mudar(novo: int) -> void:
	estado = novo
	_t_estado = 0.0
	_acertou_no_padrao = false

# ------------------------------------------------------------- autoridade
## 5: enquanto Guerra estiver vivo, ele instiga os monstros ao redor
## a atacar o jogador. E o que faz a arena virar um problema de multidao.
func _autoridade(delta: float) -> void:
	_cd_autoridade -= delta
	if _cd_autoridade > 0.0:
		return
	_cd_autoridade = CD_AUTORIDADE
	var instigados := 0
	for e in get_tree().get_nodes_in_group("inimigos"):
		if not is_instance_valid(e) or e.morto:
			continue
		if e.global_position.distance_to(global_position) < 520.0:
			e.instigar(CD_AUTORIDADE + 1.0)
			instigados += 1
	if instigados > 0:
		GameState.mensagem("Guerra ruge: %d monstros avançam" % instigados, Palette.ALERTA)

# ----------------------------------------------------------------- padroes
func _processar_golpe(delta: float) -> void:
	if _t_estado < TELEGRAFO_GOLPE:
		_encarar(alvo.global_position, delta * 2.4)
		vel = vel.lerp(Vector2.ZERO, delta * 8.0)
		return
	if not _acertou_no_padrao:
		_acertou_no_padrao = true
		_atingir_em_arco()
	if _t_estado > TELEGRAFO_GOLPE + DURACAO_GOLPE:
		_mudar(RECUPERA)

func _atingir_em_arco() -> void:
	if alvo == null or not is_instance_valid(alvo):
		return
	var d: Vector2 = alvo.global_position - global_position
	if d.length() > ALCANCE_GOLPE + 20.0:
		return
	if absf(mira.angle_to(d.normalized())) > 1.3:
		return
	_golpear(alvo)

func _processar_investida(delta: float) -> void:
	if _t_estado < TELEGRAFO_INVESTIDA:
		# trava o rumo no fim do telegrafo: da pra sair do caminho
		_encarar(alvo.global_position, delta * 3.0)
		vel = vel.lerp(Vector2.ZERO, delta * 8.0)
		_dir_investida = mira
		return
	if _t_estado < TELEGRAFO_INVESTIDA + DURACAO_INVESTIDA:
		vel = _dir_investida * VEL_INVESTIDA
		if not _acertou_no_padrao and alvo != null and is_instance_valid(alvo):
			if global_position.distance_to(alvo.global_position) < raio + 22.0:
				_acertou_no_padrao = true
				_golpear(alvo)
	else:
		_mudar(RECUPERA)

func _golpear(quem: Node) -> void:
	if not quem.has_method("receber_golpe"):
		return
	var res: Dictionary = quem.receber_golpe(dano_do_golpe(), global_position, self)
	if bool(res.get("atordoa", false)):
		_mudar(RECUPERA)
		_t_estado = -Balance.PARRY_STUN     # o atordoamento come o inicio da recuperacao

# --------------------------------------------------------------- movimento
func _mover(delta: float) -> void:
	if vel.length() < 0.01:
		return
	var antes := global_position
	global_position = dungeon.mover(global_position, vel * delta, raio)
	if estado == INVESTIDA and global_position.distance_to(antes) < vel.length() * delta * 0.3:
		_mudar(RECUPERA)     # bateu na parede no meio da investida

func _encarar(p: Vector2, peso: float) -> void:
	var d := p - global_position
	if d.length() > 0.001:
		mira = mira.lerp(d.normalized(), clampf(peso, 0.0, 1.0)).normalized()

# -------------------------------------------------------------------- dano
func levar_dano(quanto: float, _empurrao: Vector2 = Vector2.ZERO) -> void:
	if morto:
		return
	hp -= quanto
	_flash = 1.0
	if hp <= 0.0:
		hp = 0.0
		morto = true
		vel = Vector2.ZERO
		z_index = -1
		morreu.emit(self)

func esta_de_costas_para(p: Vector2) -> bool:
	return not Balance.dentro_do_cone(global_position, mira, p, 400.0)

func alertado() -> bool:
	return estado != ENTRADA

func atordoar(dur: float) -> void:
	if morto:
		return
	_mudar(RECUPERA)
	_t_estado = -dur

## 5: 30 segundos para inspecionar o corpo. Dentro da janela, a arma dropa 100%.
func janela_de_inspecao() -> float:
	if not morto or arma_coletada:
		return 0.0
	return maxf(0.0, Balance.INSPECAO_JANELA - _t_morte)

func pode_inspecionar() -> bool:
	return janela_de_inspecao() > 0.0

func telegrafo() -> float:
	if estado == GOLPE:
		return clampf(_t_estado / TELEGRAFO_GOLPE, 0.0, 1.0) if _t_estado < TELEGRAFO_GOLPE else 0.0
	if estado == INVESTIDA:
		return clampf(_t_estado / TELEGRAFO_INVESTIDA, 0.0, 1.0) if _t_estado < TELEGRAFO_INVESTIDA else 0.0
	return 0.0

func fase_ataque() -> float:
	if estado == GOLPE and _t_estado >= TELEGRAFO_GOLPE:
		return clampf((_t_estado - TELEGRAFO_GOLPE) / DURACAO_GOLPE, 0.0, 1.0)
	return 0.0

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	if morto:
		_desenhar_cadaver()
		return

	# rumo travado da investida: a faixa vermelha no chao e o aviso justo
	if estado == INVESTIDA and _t_estado < TELEGRAFO_INVESTIDA:
		var f := telegrafo()
		var comp := 620.0
		var perp := Vector2(-_dir_investida.y, _dir_investida.x)
		var pts := PackedVector2Array([
			perp * 26.0, -perp * 26.0,
			_dir_investida * comp - perp * 26.0,
			_dir_investida * comp + perp * 26.0,
		])
		draw_colored_polygon(pts, Color(Palette.ALERTA.r, Palette.ALERTA.g, Palette.ALERTA.b, 0.10 + 0.16 * f))

	Figura.cavaleiro(self, dados, mira, _t, fase_ataque(), telegrafo())

	if _flash > 0.0:
		draw_circle(Vector2(0, -30), 34.0, Color(1, 1, 1, 0.26 * _flash))

	_barra_de_vida()

func _desenhar_cadaver() -> void:
	var cor: Color = dados.get("cor", Palette.SANGUE)
	draw_circle(Vector2(0, 2), 38.0, Color(Palette.SANGUE.r, Palette.SANGUE.g, Palette.SANGUE.b, 0.45))
	draw_rect(Rect2(-26, -14, 52, 18), Palette.CONTORNO)
	draw_rect(Rect2(-23, -11, 46, 12), Palette.sombra(cor, 0.55))
	# a Espada Colossal cravada no chao, esperando
	if not arma_coletada:
		draw_line(Vector2(16, 6), Vector2(24, -56), Palette.CONTORNO, 12.0)
		draw_line(Vector2(16, 6), Vector2(24, -56), Palette.FERRO, 9.0)
		var jan := janela_de_inspecao()
		if jan > 0.0:
			# 5: o relogio de 30s correndo em volta do corpo
			var f := jan / Balance.INSPECAO_JANELA
			draw_arc(Vector2(0, -10), 46.0, -PI * 0.5, -PI * 0.5 + TAU * f, 40,
					Color(Palette.HUD_DESTAQUE.r, Palette.HUD_DESTAQUE.g,
							Palette.HUD_DESTAQUE.b, 0.75), 3.0)

func _barra_de_vida() -> void:
	var w := 64.0
	var y := -84.0
	draw_rect(Rect2(-w * 0.5 - 2.0, y - 2.0, w + 4.0, 9.0), Palette.CONTORNO)
	draw_rect(Rect2(-w * 0.5, y, w * (hp / hp_max), 5.0), Palette.SANGUE_VIVO)
