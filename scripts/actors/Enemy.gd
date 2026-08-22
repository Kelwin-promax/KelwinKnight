class_name Enemy
extends Node2D

## Inimigo comum do bestiario (4), com a percepcao do 7.7:
## cone de visao -> 0.5s de alerta -> perseguicao. Perder o jogador de vista
## joga o monstro em busca por 5s, e depois de volta ao passivo - mas ele
## NUNCA some do mapa (2: monstros persistem, fugir nao os despawna).

signal morreu(inimigo)

enum { PASSIVO, ALERTA, PERSEGUE, ATACA, BUSCA, ATORDOADO }

var dados: Dictionary
var dungeon: Dungeon
var alvo: Node2D                     # o jogador

var hp: float
var hp_max: float
var velocidade: float
var dano: float
var raio: float = 13.0

var estado: int = PASSIVO
var mira: Vector2 = Vector2.RIGHT
var vel: Vector2 = Vector2.ZERO

var _t: float = 0.0                  # relogio de animacao
var _t_estado: float = 0.0           # tempo no estado atual
var _ultima_pos_vista: Vector2 = Vector2.INF
var _destino_passeio: Vector2 = Vector2.INF
var _cd_ataque: float = 0.0
var _flash: float = 0.0
var _instigado: float = 0.0          # 5: Autoridade de Guerra
var _rastro: Array[Vector2] = []
var _t_rastro: float = 0.0

# --- ataque em duas fases: o telegrafo e o que torna o parry jogavel (7.3)
var _atacando: bool = false
var _t_ataque: float = 0.0
const WINDUP := 0.52                 # telegrafo visivel antes do impacto
const IMPACTO := 0.18                # duracao do golpe depois do impacto
const ALCANCE_ATAQUE := 40.0
const CD_ATAQUE := 1.15

# --- morte
var morto: bool = false
var consumido: bool = false
var _t_morte: float = 0.0

var rng := RandomNumberGenerator.new()

func configurar(p_dados: Dictionary, p_dungeon: Dungeon, p_alvo: Node2D, p_semente: int) -> void:
	dados = p_dados
	dungeon = p_dungeon
	alvo = p_alvo
	rng.seed = p_semente
	hp_max = float(dados["hp"])
	hp = hp_max
	# A dificuldade escala com os Cavaleiros derrubados, nao com andares.
	var agg := 1.0 + 0.08 * float(GameState.cavaleiros_mortos)
	velocidade = float(dados["vel"]) * agg
	dano = float(dados["dano"]) * agg
	var porte := maxf(float(dados.get("porte", 1.0)), 0.5)
	raio = 11.0 * sqrt(porte)
	_t = rng.randf() * 6.0
	mira = Vector2.RIGHT.rotated(rng.randf() * TAU)

func _process(delta: float) -> void:
	_t += delta
	_t_estado += delta
	_flash = maxf(0.0, _flash - delta * 3.5)
	_cd_ataque = maxf(0.0, _cd_ataque - delta)
	_instigado = maxf(0.0, _instigado - delta)

	if morto:
		_t_morte += delta
		queue_redraw()
		return

	if _atacando:
		_processar_ataque(delta)
	else:
		_processar_estado(delta)

	# regenerador: a habilidade que ele concede tambem e o que ele faz
	if String(dados["id"]) == "regen" and hp < hp_max:
		hp = minf(hp_max, hp + 1.2 * delta)

	_t_rastro += delta
	if vel.length() > 20.0 and _t_rastro >= 0.08:
		_t_rastro = 0.0
		_rastro.append(global_position)
		while _rastro.size() > 5:
			_rastro.pop_front()
	elif vel.length() <= 20.0 and _t_rastro >= 0.15 and not _rastro.is_empty():
		_t_rastro = 0.0
		_rastro.pop_front()

	queue_redraw()

# ------------------------------------------------------------------ estados
func _processar_estado(delta: float) -> void:
	var ve_o_alvo := _ve_o_alvo()

	match estado:
		PASSIVO:
			_passear(delta)
			if ve_o_alvo:
				_mudar(ALERTA)
		ALERTA:
			# 7.7: fica alerta, e so depois de 0.5s parte pra cima
			vel = vel.lerp(Vector2.ZERO, delta * 8.0)
			_encarar(alvo.global_position, delta * 9.0)
			if not ve_o_alvo:
				_mudar(PASSIVO)          # saiu do cone antes do alerta fechar
			elif _t_estado >= Balance.ALERTA_ATRASO:
				_ultima_pos_vista = alvo.global_position
				_mudar(PERSEGUE)
		PERSEGUE:
			var d := alvo.global_position - global_position
			_mover_para(alvo.global_position, delta, 1.0)
			_encarar(alvo.global_position, delta * 7.0)
			if ve_o_alvo or _instigado > 0.0:
				_ultima_pos_vista = alvo.global_position
			if d.length() <= ALCANCE_ATAQUE and _cd_ataque <= 0.0:
				_iniciar_ataque()
			elif not ve_o_alvo and _instigado <= 0.0 and _t_estado > 0.6:
				# 7.8: perdeu de vista -> vai ate onde viu por ultimo
				_mudar(BUSCA)
		BUSCA:
			# 7.8: procura por 5s; se nao achar, volta ao passivo
			if _ultima_pos_vista != Vector2.INF:
				_mover_para(_ultima_pos_vista, delta, 0.85)
				if global_position.distance_to(_ultima_pos_vista) < 24.0:
					_ultima_pos_vista = Vector2.INF
			else:
				_passear(delta)
			if ve_o_alvo:
				_mudar(PERSEGUE)
			elif _t_estado >= Balance.BUSCA_DURACAO:
				_mudar(PASSIVO)
		ATORDOADO:
			vel = vel.lerp(Vector2.ZERO, delta * 6.0)
			if _t_estado >= _dur_atordoado:
				_mudar(PERSEGUE if ve_o_alvo else BUSCA)

	_aplicar_movimento(delta)

var _dur_atordoado: float = 0.5

func _mudar(novo: int) -> void:
	estado = novo
	_t_estado = 0.0

## 7.7: dentro do cone E com linha de visao livre. Pedra bloqueia.
func _ve_o_alvo() -> bool:
	if alvo == null or not is_instance_valid(alvo):
		return false
	var alcance := Balance.CONE_ALCANCE
	if String(dados["id"]) == "vigia":
		alcance *= 1.35     # Vigia Carnica enxerga mais longe: e o que ela e
	# 7.8: agachado nao te apaga do mapa, so encolhe muito o alcance em que
	# voce e notado - da para passar por perto se o monstro estiver de lado.
	if alvo.has_method("esta_escondido") and alvo.esta_escondido():
		alcance *= 0.35
	if not Balance.dentro_do_cone(global_position, mira, alvo.global_position, alcance):
		return false
	return dungeon.linha_livre(global_position, alvo.global_position)

## O jogador esta fora do meu cone? Entao o golpe dele e pelas costas (7.7).
func esta_de_costas_para(p: Vector2) -> bool:
	if estado == ATORDOADO:
		return true
	return not Balance.dentro_do_cone(global_position, mira, p, Balance.CONE_ALCANCE)

func alertado() -> bool:
	return estado == PERSEGUE or estado == ATACA or _atacando

# ---------------------------------------------------------------- movimento
func _passear(delta: float) -> void:
	if _destino_passeio == Vector2.INF or global_position.distance_to(_destino_passeio) < 20.0:
		_destino_passeio = dungeon.chao_aleatorio(rng, global_position, 60.0)
	_mover_para(_destino_passeio, delta, 0.42)
	if vel.length() > 4.0:
		_encarar(global_position + vel, delta * 3.0)

func _mover_para(p: Vector2, delta: float, fator: float) -> void:
	var d := p - global_position
	if d.length() < 0.001:
		return
	var v := velocidade * fator * (1.35 if _instigado > 0.0 else 1.0)
	vel = vel.lerp(d.normalized() * v, delta * 7.0)

func _aplicar_movimento(delta: float) -> void:
	if vel.length() < 0.01:
		return
	var antes := global_position
	global_position = dungeon.mover(global_position, vel * delta, raio)
	# Bateu na parede? Escolhe outro destino em vez de ficar raspando nela.
	if global_position.distance_to(antes) < vel.length() * delta * 0.25:
		_destino_passeio = Vector2.INF
		vel *= 0.4

func _encarar(p: Vector2, peso: float) -> void:
	var d := p - global_position
	if d.length() > 0.001:
		mira = mira.lerp(d.normalized(), clampf(peso, 0.0, 1.0)).normalized()

# ------------------------------------------------------------------ ataque
func _iniciar_ataque() -> void:
	_atacando = true
	_t_ataque = 0.0
	estado = ATACA
	vel = Vector2.ZERO

func _processar_ataque(delta: float) -> void:
	_t_ataque += delta
	if _t_ataque < WINDUP:
		# telegrafo: encara o alvo devagar, para dar pra ler a direcao
		_encarar(alvo.global_position, delta * 3.0)
		vel = vel.lerp(Vector2.ZERO, delta * 10.0)
	elif _t_ataque < WINDUP + delta and _t_ataque >= WINDUP:
		pass
	_aplicar_movimento(delta)

	# o impacto acontece exatamente ao fim do windup
	if _t_ataque >= WINDUP and not _impacto_resolvido:
		_impacto_resolvido = true
		_resolver_impacto()
	if _t_ataque >= WINDUP + IMPACTO:
		_atacando = false
		_impacto_resolvido = false
		_cd_ataque = CD_ATAQUE
		_mudar(PERSEGUE)

var _impacto_resolvido: bool = false

func _resolver_impacto() -> void:
	if alvo == null or not is_instance_valid(alvo):
		return
	var d := alvo.global_position - global_position
	if d.length() > ALCANCE_ATAQUE + 18.0:
		return                                   # o jogador saiu do alcance
	if not alvo.has_method("receber_golpe"):
		return
	var res: Dictionary = alvo.receber_golpe(dano, global_position, self)
	if bool(res.get("atordoa", false)):
		atordoar(Balance.PARRY_STUN)

## Fase do golpe para o desenho: 0 no comeco do telegrafo, 1 no impacto.
func fase_ataque() -> float:
	if not _atacando:
		return 0.0
	if _t_ataque < WINDUP:
		return 0.0
	return clampf((_t_ataque - WINDUP) / IMPACTO, 0.0, 1.0)

func telegrafo() -> float:
	if not _atacando or _t_ataque >= WINDUP:
		return 0.0
	return clampf(_t_ataque / WINDUP, 0.0, 1.0)

# -------------------------------------------------------------------- dano
func levar_dano(quanto: float, empurrao: Vector2 = Vector2.ZERO) -> void:
	if morto:
		return
	hp -= quanto
	_flash = 1.0
	vel += empurrao
	# Levar porrada acorda o monstro mesmo se veio pelas costas.
	if estado == PASSIVO or estado == BUSCA or estado == ALERTA:
		_ultima_pos_vista = alvo.global_position if alvo else global_position
		_mudar(PERSEGUE)
	if hp <= 0.0:
		_morrer()

func atordoar(dur: float) -> void:
	if morto:
		return
	_atacando = false
	_impacto_resolvido = false
	_dur_atordoado = dur
	_mudar(ATORDOADO)

## 5: a Autoridade de Guerra instiga os monstros ao redor.
func instigar(dur: float) -> void:
	if morto:
		return
	_instigado = maxf(_instigado, dur)
	if estado != ATORDOADO:
		_ultima_pos_vista = alvo.global_position if alvo else global_position
		if estado != PERSEGUE:
			_mudar(PERSEGUE)

func _morrer() -> void:
	morto = true
	_atacando = false
	vel = Vector2.ZERO
	z_index = -1          # cadaveres ficam por baixo de quem anda
	morreu.emit(self)

## Da para comer? (3.3) Cadaver ainda nao consumido.
func pode_consumir() -> bool:
	return morto and not consumido

# ------------------------------------------------------------------ desenho
## Qual pose da folha corresponde ao estado de agora.
##
## A ordem segue a mesma escala de prioridade do jogador: primeiro o que tirou o
## controle do monstro (morrer, apanhar), depois o que ele escolheu fazer
## (atacar), e so no fim o deslocamento.
func _anim_atual() -> Array:
	if morto:
		return ["morto", 0.0]
	if estado == ATORDOADO:
		return ["dano", 0.0]
	if _atacando:
		# um progresso so, cobrindo telegrafo e impacto: assim a garra sobe
		# durante o windup e desce no quadro em que o dano sai.
		var total := WINDUP + IMPACTO
		return ["atacar", clampf(_t_ataque / total, 0.0, 1.0)]
	if vel.length() > 8.0:
		return ["andar", 0.0]
	return ["parado", 0.0]

## A folha manda quando existe; sem ela o bicho volta a ser desenhado por
## codigo e o jogo segue igual.
func _desenhar_corpo() -> bool:
	if not SpriteCriatura.disponivel(String(dados["id"])):
		return false
	# a sombra vem antes do corpo, senao ela pinta por cima do bicho
	Figura.sombra(self, raio)
	var porte := float(dados.get("porte", 1.0))
	var altura := SpriteCriatura.ALTURA_BASE * porte
	if String(dados.get("id", "")) == "carniceiro":
		altura = SpriteJogador.ALTURA_ALVO * 4.0
	elif String(dados.get("id", "")) == "rastejador":
		altura = SpriteJogador.ALTURA_ALVO * 0.5
	var an := _anim_atual()
	var lado := signf(mira.x) if absf(mira.x) > 0.05 else 1.0
	return SpriteCriatura.desenhar(self, String(dados["id"]), String(an[0]), _t,
			float(an[1]), lado, altura)

func _draw() -> void:
	for i in range(_rastro.size()):
		var a := 0.12 * (float(i + 1) / maxf(float(_rastro.size()), 1.0))
		var ofs := _rastro[i] - global_position
		draw_circle(ofs + Vector2(0, -10), raio * 0.8,
				Color(Palette.CONTORNO.r, Palette.CONTORNO.g, Palette.CONTORNO.b, a))

	if morto:
		# O cadaver da folha e um quadro proprio (a ultima pose da banda de
		# morte); sem folha, cai no borrao de sangue do Figura.
		if not _desenhar_corpo():
			Figura.cadaver(self, dados, 1.0 if not consumido else 0.0)
		return

	var marca := 0
	if estado == ALERTA or _atacando:
		marca = 1
	elif estado == BUSCA:
		marca = 2

	# 7.7: o cone so aparece quando o monstro esta olhando ativamente.
	if estado == PASSIVO or estado == ALERTA or estado == BUSCA:
		_desenhar_cone()

	if not _desenhar_corpo():
		Figura.criatura(self, dados, mira, _t, fase_ataque(), marca)
	else:
		# 7.7: com a folha no lugar do boneco, o ! e o ? do alerta continuam
		# precisando aparecer - e sinal de leitura, nao enfeite.
		var altura := SpriteCriatura.ALTURA_BASE * float(dados.get("porte", 1.0))
		if String(dados.get("id", "")) == "carniceiro":
			altura = SpriteJogador.ALTURA_ALVO * 4.0
		elif String(dados.get("id", "")) == "rastejador":
			altura = SpriteJogador.ALTURA_ALVO * 0.5
		var topo := -altura
		if marca == 1:
			Figura.marca_alerta(self, topo - 16.0, Palette.ALERTA, true)
		elif marca == 2:
			Figura.marca_alerta(self, topo - 16.0, Palette.BUSCA, false)

	if telegrafo() > 0.0:
		var r := 26.0 + 16.0 * telegrafo()
		draw_arc(Vector2(0, -14), r, 0.0, TAU, 28,
				Color(Palette.ALERTA.r, Palette.ALERTA.g, Palette.ALERTA.b, 0.20 + 0.4 * telegrafo()), 2.0)

	if _flash > 0.0:
		draw_circle(Vector2(0, -14), 20.0, Color(1, 1, 1, 0.30 * _flash))

	_barra_de_vida()

func _desenhar_cone() -> void:
	var a := mira.angle()
	var alcance := Balance.CONE_ALCANCE * 0.42
	var cor := Palette.ALERTA if estado == ALERTA else Palette.BUSCA
	if estado == PASSIVO:
		cor = Palette.HUD_FRACO
	var alfa := 0.05 if estado == PASSIVO else 0.10

	var origin := Vector2(0, -10)
	var pts := PackedVector2Array([origin])
	var n := 12
	for i in range(n + 1):
		var f := float(i) / float(n)
		var ang := a - Balance.CONE_ANGULO + 2.0 * Balance.CONE_ANGULO * f
		pts.append(origin + Vector2(cos(ang), sin(ang)) * alcance)
	draw_colored_polygon(pts, Color(cor.r, cor.g, cor.b, alfa))

	var esq := origin + Vector2(cos(a - Balance.CONE_ANGULO), sin(a - Balance.CONE_ANGULO)) * alcance
	var dir := origin + Vector2(cos(a + Balance.CONE_ANGULO), sin(a + Balance.CONE_ANGULO)) * alcance
	draw_line(origin, esq, Color(cor.r, cor.g, cor.b, alfa * 2.0), 1.5)
	draw_line(origin, dir, Color(cor.r, cor.g, cor.b, alfa * 2.0), 1.5)

func _barra_de_vida() -> void:
	if hp >= hp_max:
		return
	var w := 26.0
	var y := -46.0 * float(dados.get("porte", 1.0))
	draw_rect(Rect2(-w * 0.5 - 1.0, y - 1.0, w + 2.0, 5.0), Palette.CONTORNO)
	draw_rect(Rect2(-w * 0.5, y, w * (hp / hp_max), 3.0), Palette.HUD_VIDA)
