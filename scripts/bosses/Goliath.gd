extends EnemyBase
class_name Goliath
## The final boss. Three HP-gated phases, each escalating the same three tools --
## a swept laser beam, a spread of lobbed projectiles, and a grab -- rather than
## introducing new ones, so the fight reads as one creature getting more desperate
## instead of a checklist of unrelated gimmicks.
##
## The spec calls for a Parry to deny the grab; Player has no parry system, so per
## its own fallback clause ("ou Dash pra sair do alcance") the grab is dash-escapable
## instead -- `is_dashing()`/`is_invulnerable()` on Player cover that for free.

signal phase_changed(phase: int)

enum Phase { INTRO, ESCALATION, FRENZY }

const ORB_TEXTURE := preload("res://assets/sprites/fx_frames/dust_land.png")
const BEAM_COLOR := Color(1.0, 0.35, 0.25, 0.85)
const BEAM_WIDTH := 14.0
const BEAM_LENGTH := 1500.0
const GRAB_RANGE := 220.0
const GRAB_PULL_TIME := 0.5
const GRAB_HOLD_TIME := 1.0
const GRAB_THROW_SPEED := 520.0

var phase: Phase = Phase.INTRO
var _busy: bool = false
var _wall_volleys: int = 0
var _cooldown_timer: float = 1.0
var _last_grab_time: float = -99.0

@onready var beam_a: Line2D = $BeamA
@onready var beam_b: Line2D = $BeamB

func _on_ready() -> void:
	detect_radius = 3000.0
	attack_range = 3000.0
	max_health = 260
	contact_damage = 0   # all damage comes from the beam/grab/projectiles, not passive touch
	knockback_speed = 400.0
	knockback_time = 0.8
	affected_by_gravity = false
	beam_a.visible = false
	beam_b.visible = false
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")

func _think(delta: float) -> void:
	_update_phase()
	_cooldown_timer -= delta
	if _busy or _cooldown_timer > 0.0:
		return
	_cooldown_timer = _cooldown_for_phase()
	_run_attack_cycle()

func _update_phase() -> void:
	if phase != Phase.FRENZY and health <= max_health * 0.10:
		phase = Phase.FRENZY
		phase_changed.emit(2)
	elif phase == Phase.INTRO and health <= max_health * 0.35:
		phase = Phase.ESCALATION
		phase_changed.emit(1)

func _cooldown_for_phase() -> float:
	match phase:
		Phase.INTRO: return 1.0
		Phase.ESCALATION: return 0.6
		_: return 0.3

func _run_attack_cycle() -> void:
	_busy = true
	match phase:
		Phase.INTRO:
			await _laser_sweep(beam_a, 3, 0.8, 0.5)
			_wall_volleys += 1
			if _wall_volleys % 2 == 0:
				_fire_projectile_wall(5, deg_to_rad(70))
		Phase.ESCALATION:
			await _laser_sweep(beam_a, 2, 0.65, 0.3)   # ~20% faster than phase 1
			await _attempt_grab()
			_fire_projectile_wall(8, TAU)
		Phase.FRENZY:
			_laser_sweep(beam_b, 2, 0.6, 0.25)   # fired without awaiting: overlaps beam_a below
			await _laser_sweep(beam_a, 2, 0.6, 0.25)
			if Time.get_ticks_msec() / 1000.0 - _last_grab_time >= 3.0:
				await _attempt_grab()
			_fire_projectile_wall(12, TAU)
	_busy = false

# ------------------------------------------------------------------- laser ----

func _laser_sweep(beam: Line2D, count: int, beam_time: float, gap_time: float) -> void:
	var base_angle := _direction_to_player().angle()
	var spread := deg_to_rad(35)
	for i in range(count):
		var t: float = 0.0 if count == 1 else float(i) / float(count - 1)
		var angle: float = base_angle + lerp(-spread, spread, t)
		await _fire_beam(beam, Vector2.RIGHT.rotated(angle), beam_time)
		if i < count - 1:
			await get_tree().create_timer(gap_time).timeout

func _fire_beam(beam: Line2D, dir: Vector2, duration: float) -> void:
	beam.points = PackedVector2Array([Vector2.ZERO, dir * BEAM_LENGTH])
	beam.visible = true
	var hit_done := false
	var t: float = 0.0
	while t < duration:
		var dt := get_physics_process_delta_time()
		await get_tree().physics_frame
		t += dt
		if not hit_done and player and is_instance_valid(player):
			var to_player: Vector2 = player.global_position - global_position
			var along: float = to_player.dot(dir)
			if along > 0.0 and along < BEAM_LENGTH:
				var perp: float = absf(to_player.x * dir.y - to_player.y * dir.x)
				if perp <= BEAM_WIDTH and player.has_method("take_damage"):
					player.take_damage(1 if phase == Phase.INTRO else 2, global_position)
					hit_done = true
	beam.visible = false

# --------------------------------------------------------------- projectiles ---

func _fire_projectile_wall(count: int, spread_angle: float) -> void:
	var base_angle := _direction_to_player().angle()
	for i in range(count):
		var angle: float
		if spread_angle >= TAU - 0.01:
			angle = base_angle + (float(i) / float(count)) * TAU
		else:
			var t: float = 0.0 if count == 1 else float(i) / float(count - 1)
			angle = base_angle + lerp(-spread_angle * 0.5, spread_angle * 0.5, t)
		ProjectilePool.fire(global_position, Vector2.RIGHT.rotated(angle), 250.0, ORB_TEXTURE, 1)

# --------------------------------------------------------------------- grab ---

func _attempt_grab() -> void:
	if player == null or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) > GRAB_RANGE:
		return

	# Dash (or any existing i-frames) is this fight's counter to the grab, in place
	# of a dedicated Parry the player kit does not have.
	if player.has_method("is_dashing") and (player.is_dashing() or player.is_invulnerable()):
		return

	_last_grab_time = Time.get_ticks_msec() / 1000.0
	player.velocity = Vector2.ZERO
	var pull_target: Vector2 = global_position + (player.global_position - global_position).normalized() * 60.0
	var t := create_tween()
	t.tween_property(player, "global_position", pull_target, GRAB_PULL_TIME)
	await t.finished
	if player == null or not is_instance_valid(player):
		return

	await get_tree().create_timer(GRAB_HOLD_TIME).timeout
	if player == null or not is_instance_valid(player):
		return

	var away := signf(player.global_position.x - global_position.x)
	if is_zero_approx(away):
		away = -1.0
	if player.has_method("take_damage"):
		player.take_damage(2, global_position)
	player.velocity = Vector2(away * GRAB_THROW_SPEED, -GRAB_THROW_SPEED * 0.6)

func _on_death() -> void:
	beam_a.visible = false
	beam_b.visible = false
