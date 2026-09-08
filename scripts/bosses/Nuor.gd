extends EnemyBase
class_name Nuor
## Nuor, "The Titan's Ascendant" -- o chefe da arena final.
##
## O Goliath fica parado e cobre a sala de feixes: a pressao dele e' o espaco.
## Nuor faz o oposto e ANDA ate o jogador, e cada ferramenta cobre uma faixa de
## distancia diferente -- soco e chute coladinho, o salto para fechar a media, o
## feixe para punir quem fica longe. Recuar nao alivia, so troca qual ameaca
## chega; e' isso que obriga o jogador a escolher uma distancia em vez de fugir.
##
## Golpes tem armadura: levar dano no meio de uma animacao nao a cancela. Sem
## isso o jogador trancaria o chefe encostando nele, e a briga viraria um
## atordoamento continuo.

signal phase_changed(phase: int)

enum Phase { STEADY, RELENTLESS, ASCENDANT }

const MELEE_RANGE := 190.0     ## a partir daqui o soco/chute alcanca
const SLAM_RANGE := 700.0      ## alcance maximo do salto
const AGGRO_RANGE := 2400.0

const PUNCH_REACH := 210.0
const KICK_REACH := 250.0
const PUNCH_DAMAGE := 1
const KICK_DAMAGE := 2

const BEAM_WINDUP := 0.55      ## telegrafo: da' para sair andando se reagir
const BEAM_TIME := 0.5
const BEAM_LENGTH := 1600.0
const BEAM_WIDTH := 26.0
const BEAM_DAMAGE := 2

const SLAM_RISE := 0.42
const SLAM_JUMP_SPEED := 780.0
const SHOCKWAVE_RADIUS := 300.0
const SHOCKWAVE_DAMAGE := 2

var phase: Phase = Phase.STEADY

var _busy: bool = false
var _cooldown: float = 1.2
var _melee_toggle: bool = false

@onready var beam: Line2D = $Beam

func _on_ready() -> void:
	detect_radius = AGGRO_RANGE
	attack_range = 0.0        # a escolha de golpe e' minha, nao do _think da base
	max_health = 320
	contact_damage = 0        # todo dano vem dos golpes, nao do encostao
	knockback_speed = 70.0    # um titan nao recua com uma espadada
	knockback_time = 0.15
	affected_by_gravity = true
	chase_speed = 165.0
	beam.visible = false
	_play("idle")

# ------------------------------------------------------------------ cerebro ---

func _think(delta: float) -> void:
	_update_phase()

	if not is_on_floor():
		velocity.y += gravity * delta

	if _busy:
		return

	_cooldown -= delta
	var d := _distance_to_player()
	if d > AGGRO_RANGE:
		velocity.x = 0.0
		_play("idle")
		return

	if _cooldown <= 0.0:
		_cooldown = _cooldown_for_phase()
		_choose_attack(d)
		return

	_advance(d)

func _update_phase() -> void:
	if phase != Phase.ASCENDANT and health <= max_health * 0.25:
		phase = Phase.ASCENDANT
		phase_changed.emit(2)
	elif phase == Phase.STEADY and health <= max_health * 0.60:
		phase = Phase.RELENTLESS
		phase_changed.emit(1)

func _cooldown_for_phase() -> float:
	match phase:
		Phase.STEADY: return 1.5
		Phase.RELENTLESS: return 1.0
		_: return 0.55

## Anda ate entrar no alcance do corpo a corpo; parado quando ja esta la.
func _advance(d: float) -> void:
	if d <= MELEE_RANGE * 0.8:
		velocity.x = 0.0
		_play("idle")
		return
	_face_player()
	velocity.x = (1.0 if facing_right else -1.0) * chase_speed
	_play("walk")

## Cada faixa de distancia tem sua resposta -- e' o que faz recuar nao ser saida.
func _choose_attack(d: float) -> void:
	if d <= MELEE_RANGE:
		_melee_toggle = not _melee_toggle
		if _melee_toggle:
			_do_punch()
		else:
			_do_kick()
	elif d <= SLAM_RANGE:
		_do_slam()
	else:
		_do_beam()

# ------------------------------------------------------------------- golpes ---

func _do_punch() -> void:
	_busy = true
	_face_player()
	velocity.x = 0.0
	_play("punch", true)
	await get_tree().create_timer(0.16).timeout
	_melee_hit(PUNCH_REACH, PUNCH_DAMAGE)
	await get_tree().create_timer(0.22).timeout
	_busy = false

func _do_kick() -> void:
	_busy = true
	_face_player()
	velocity.x = 0.0
	_play("kick", true)
	await get_tree().create_timer(0.20).timeout
	_melee_hit(KICK_REACH, KICK_DAMAGE)
	await get_tree().create_timer(0.26).timeout
	_busy = false

func _do_beam() -> void:
	_busy = true
	_face_player()
	velocity.x = 0.0
	_play("beam", true)

	# telegrafo: o feixe aparece fino e apagado antes de existir de verdade
	var dir := Vector2.RIGHT if facing_right else Vector2.LEFT
	beam.points = PackedVector2Array([Vector2.ZERO, dir * BEAM_LENGTH])
	beam.width = 4.0
	beam.modulate.a = 0.35
	beam.visible = true
	await get_tree().create_timer(BEAM_WINDUP).timeout
	if state == State.DEAD:
		return

	beam.width = BEAM_WIDTH
	beam.modulate.a = 1.0
	var hit := false
	var t := 0.0
	while t < BEAM_TIME and state != State.DEAD:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if hit or player == null or not is_instance_valid(player):
			continue
		var to_p: Vector2 = player.global_position - global_position
		var along := to_p.dot(dir)
		if along > 0.0 and along < BEAM_LENGTH and absf(to_p.y) <= BEAM_WIDTH:
			player.take_damage(BEAM_DAMAGE, global_position)
			hit = true

	beam.visible = false
	if phase == Phase.ASCENDANT and state != State.DEAD:
		# na ultima faixa o feixe vem em dois tempos, sem novo telegrafo
		await get_tree().create_timer(0.18).timeout
		await _second_beam(dir)
	_busy = false

func _second_beam(dir: Vector2) -> void:
	beam.visible = true
	var hit := false
	var t := 0.0
	while t < BEAM_TIME * 0.7 and state != State.DEAD:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if hit or player == null or not is_instance_valid(player):
			continue
		var to_p: Vector2 = player.global_position - global_position
		var along := to_p.dot(dir)
		if along > 0.0 and along < BEAM_LENGTH and absf(to_p.y) <= BEAM_WIDTH:
			player.take_damage(BEAM_DAMAGE, global_position)
			hit = true
	beam.visible = false

## Salta na direcao do jogador e bate no chao: fecha a media distancia e cobra
## quem tenta so manter espaco sem sair da linha.
func _do_slam() -> void:
	_busy = true
	_face_player()
	velocity.x = 0.0
	_play("slam", true)
	await get_tree().create_timer(0.22).timeout      # antecipacao
	if state == State.DEAD:
		return

	var dx := 0.0
	if player and is_instance_valid(player):
		dx = clampf(player.global_position.x - global_position.x, -SLAM_RANGE, SLAM_RANGE)
	velocity = Vector2(dx / SLAM_RISE, -SLAM_JUMP_SPEED)

	await get_tree().create_timer(0.12).timeout      # sai do chao antes de testar
	while not is_on_floor() and state != State.DEAD:
		await get_tree().physics_frame

	velocity.x = 0.0
	if state != State.DEAD:
		EffectPool.spawn("land", global_position, false, 3.0, 0.5)
		_shockwave()
	await get_tree().create_timer(0.30).timeout
	_busy = false

# ------------------------------------------------------------------ acertos ---

## Golpe frontal: so pega quem esta na frente, perto do chao do chefe e dentro do
## alcance. Dash e i-frames do jogador continuam valendo -- quem checa e' o
## proprio take_damage dele.
func _melee_hit(reach: float, damage: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var to_p: Vector2 = player.global_position - global_position
	if absf(to_p.y) > 140.0:
		return
	var forward := 1.0 if facing_right else -1.0
	if to_p.x * forward < -40.0:
		return
	if absf(to_p.x) > reach:
		return
	player.take_damage(damage, global_position)

## A onda da aterrissagem so alcanca quem esta no chao: pular na hora certa e' a
## saida, e isso da' ao salto uma resposta diferente da do feixe.
func _shockwave() -> void:
	if player == null or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) > SHOCKWAVE_RADIUS:
		return
	if player.has_method("is_on_floor") and not player.is_on_floor():
		return
	player.take_damage(SHOCKWAVE_DAMAGE, global_position)

# ------------------------------------------------------------------ auxilio ---

func _face_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	facing_right = player.global_position.x >= global_position.x
	if sprite:
		sprite.flip_h = not facing_right

func _play(anim: String, restart: bool = false) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		return
	if restart or sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)

## A base vira o sprite pela velocidade; durante um golpe o chefe esta parado e
## isso o faria voltar para a direcao antiga no meio da animacao.
func _face_travel_direction() -> void:
	if _busy:
		return
	super()

func _on_death() -> void:
	beam.visible = false
	_busy = true
