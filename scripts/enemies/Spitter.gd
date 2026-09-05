extends EnemyBase
class_name Spitter
## Stationary turret. Never chases -- `patrol_speed`/`chase_speed` are 0, so
## EnemyBase just leaves it in place -- and unloads two bolts a beat apart whenever
## the player is anywhere in its long detection range.

const PROJECTILE_TEXTURE := preload("res://assets/sprites/enemy_frames/spitter_projectile.png")
const PROJECTILE_SPEED := 200.0
const PROJECTILE_DAMAGE := 1
const VOLLEY_GAP := 0.3

func _on_ready() -> void:
	detect_radius = 600.0
	attack_range = 600.0
	attack_cooldown = 2.5
	patrol_speed = 0.0
	chase_speed = 0.0
	max_health = 30
	contact_damage = 0   # damage comes from its bolts, not from being walked into
	knockback_speed = 180.0
	knockback_time = 0.3
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")

func _perform_attack() -> void:
	velocity = Vector2.ZERO
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("spit"):
		sprite.play("spit")

	_fire_bolt()
	var t := create_tween()
	t.tween_interval(VOLLEY_GAP)
	t.tween_callback(_fire_bolt)

func _fire_bolt() -> void:
	if player == null or not is_instance_valid(player):
		return
	ProjectilePool.fire(global_position, _direction_to_player(), PROJECTILE_SPEED,
		PROJECTILE_TEXTURE, PROJECTILE_DAMAGE)
