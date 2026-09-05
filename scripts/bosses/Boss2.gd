extends EnemyBase
class_name Boss2
## "The Horrid" -- Level 2's boss, and the payoff for carrying Boss 1's lantern.
## No bespoke art exists for a light-sensitive horror either, so it borrows the
## Harpy's flight rig and darkens it to a near-black silhouette. Caught inside the
## player's lantern glow it flinches into an exposed stagger; left in the dark it
## dives freely.

const LIGHT_EXPOSURE_RADIUS := 260.0
const EXPOSED_SPEED_MULT := 0.35

var _exposed: bool = false

func _on_ready() -> void:
	detect_radius = 500.0
	attack_range = 260.0
	attack_cooldown = 2.6
	chase_speed = 130.0
	max_health = 70
	contact_damage = 1
	knockback_speed = 220.0
	knockback_time = 0.5
	affected_by_gravity = false
	sprite.modulate = Color(0.12, 0.08, 0.12)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("fly"):
		sprite.play("fly")

func _physics_process(delta: float) -> void:
	_exposed = _player_light_reaches_here()
	sprite.modulate = Color(0.55, 0.45, 0.4) if _exposed else Color(0.12, 0.08, 0.12)
	super._physics_process(delta)

func _player_light_reaches_here() -> bool:
	if not Progress.has("lantern") or player == null or not is_instance_valid(player):
		return false
	var lantern: Node = player.get("lantern")
	if lantern == null or not lantern.get("enabled"):
		return false
	return global_position.distance_to(player.global_position) <= LIGHT_EXPOSURE_RADIUS

func _chase(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var target_pos: Vector2 = player.global_position + Vector2(0.0, -160.0)
	var speed: float = chase_speed * (EXPOSED_SPEED_MULT if _exposed else 1.0)
	velocity = (target_pos - global_position).normalized() * speed
	_face_travel_direction()

func _perform_attack() -> void:
	if _exposed:
		return   # the light keeps it from pressing an attack
	var dir := _direction_to_player()
	dir.y = maxf(dir.y, 0.4)
	velocity = dir.normalized() * 260.0
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("dive"):
		sprite.play("dive")

func _on_death() -> void:
	Progress.grant("double_jump")
