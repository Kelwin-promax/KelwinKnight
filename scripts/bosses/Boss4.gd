extends EnemyBase
class_name Boss4
## "The Wind-Up Soldier" -- Level 4's boss. Reuses the second armoured statue
## (a brassy tint stands in for its own dedicated art) and expresses its wind-up-toy
## nature entirely through pacing: a fast, aggressive burst that visibly slows and
## winds down into a wide-open punish window, on a loop.

const BURST_TIME := 4.0
const REWIND_TIME := 2.5
const BURST_SPEED := 190.0
const REWIND_SPEED := 40.0

enum ClockState { BURST, REWIND }
var clock_state: ClockState = ClockState.BURST
var _phase_timer: float = BURST_TIME

func _on_ready() -> void:
	detect_radius = 2000.0
	attack_range = 90.0
	max_health = 110
	contact_damage = 1
	knockback_speed = 200.0
	knockback_time = 0.4
	sprite.modulate = Color(0.85, 0.6, 0.35)
	_enter_burst()

func _think(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		if clock_state == ClockState.BURST:
			_enter_rewind()
		else:
			_enter_burst()

	if not is_on_floor():
		velocity.y += gravity * delta

	if clock_state == ClockState.REWIND:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		return

	if _distance_to_player() <= attack_range and _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		_perform_attack()
	else:
		velocity.x = _direction_to_player().x * chase_speed

func _enter_burst() -> void:
	clock_state = ClockState.BURST
	_phase_timer = BURST_TIME
	chase_speed = BURST_SPEED
	attack_cooldown = 0.8
	sprite.speed_scale = 1.6

func _enter_rewind() -> void:
	clock_state = ClockState.REWIND
	_phase_timer = REWIND_TIME
	chase_speed = REWIND_SPEED
	sprite.speed_scale = 0.4
	sprite.modulate = Color(1.1, 0.85, 0.55)

func _perform_attack() -> void:
	velocity.x = _direction_to_player().x * (chase_speed * 1.3)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if clock_state == ClockState.BURST:
		sprite.modulate = Color(0.85, 0.6, 0.35)

func _on_death() -> void:
	Progress.grant("vitality_boost")
