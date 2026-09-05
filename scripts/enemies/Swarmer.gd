extends EnemyBase
class_name Swarmer

var hover_timer: float = 0.0

func _on_ready() -> void:
	detect_radius = 350.0
	attack_range = 100.0
	attack_cooldown = 2.0
	patrol_speed = 40.0
	chase_speed = 180.0
	max_health = 25
	contact_damage = 1
	knockback_speed = 200.0
	knockback_time = 0.5
	affected_by_gravity = false
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("hover"):
		sprite.play("hover")

func _chase(delta: float) -> void:
	if hover_timer > 0.0:
		hover_timer -= delta
		velocity = Vector2.ZERO
		return
	
	var dir := _direction_to_player()
	dir.y = signf(dir.y) if dir.y != 0 else 1.0
	dir.x = signf(dir.x) if dir.x != 0 else 1.0
	
	velocity = dir.normalized() * chase_speed

func _perform_attack() -> void:
	hover_timer = 2.0
	velocity = Vector2.ZERO
