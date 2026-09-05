extends EnemyBase
class_name Boss3
## "The Marionette" -- Level 3's boss, fought up in the warehouse's vertical shaft.
## Reuses the armoured statue art (tinted pale and hung with the stage's chain
## sprite in the scene) since no puppet was drawn for this cast. Its whole identity
## is in the movement: instead of walking it jerks to a new spot near the player on
## a string-cut cadence, then snaps into a straight lunge.

const JERK_INTERVAL := 0.7
const JERK_DISTANCE := 90.0
const LUNGE_INTERVAL := 2.2
const LUNGE_SPEED := 420.0

var _jerk_timer: float = 0.0
var _lunge_timer: float = LUNGE_INTERVAL
var _lunging: bool = false

func _on_ready() -> void:
	detect_radius = 2000.0
	attack_range = 70.0
	attack_cooldown = 1.0
	max_health = 90
	contact_damage = 1
	knockback_speed = 260.0
	knockback_time = 0.55
	affected_by_gravity = false   # strings hold it up; it never falls
	sprite.modulate = Color(0.72, 0.76, 0.85)

func _think(delta: float) -> void:
	_lunge_timer -= delta

	if _lunging:
		if is_on_wall() or _distance_to_player() < 40.0:
			_lunging = false
			velocity = Vector2.ZERO
		return

	if _lunge_timer <= 0.0 and _distance_to_player() < 500.0:
		_lunging = true
		_lunge_timer = LUNGE_INTERVAL
		velocity = _direction_to_player() * LUNGE_SPEED
		var t := create_tween()
		t.tween_interval(0.5)
		t.tween_callback(func(): _lunging = false)
		return

	_jerk_timer -= delta
	if _jerk_timer <= 0.0:
		_jerk_timer = JERK_INTERVAL
		_jerk_toward_player()
	else:
		velocity = Vector2.ZERO

func _jerk_toward_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	var dir := _direction_to_player()
	var side := Vector2(-dir.y, dir.x) * (1.0 if randf() < 0.5 else -1.0)
	var target := global_position + dir * JERK_DISTANCE + side * (JERK_DISTANCE * 0.5)
	global_position = global_position.lerp(target, 0.85)
	EffectPool.spawn("land", global_position, false, 0.5)

func _on_death() -> void:
	Progress.grant("extra_dash")
