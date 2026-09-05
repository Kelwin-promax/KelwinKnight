extends EnemyBase
class_name Creeper
## Ground crawler. Shuffles along a patrol line until the player comes close, then
## runs them down and bites. The starter enemy, so its tell is slow and readable.

func _on_ready() -> void:
	detect_radius = 300.0
	attack_range = 60.0
	attack_cooldown = 1.2
	patrol_speed = 80.0
	chase_speed = 150.0
	max_health = 20
	health = max_health
	contact_damage = 1
	knockback_speed = 150.0
	knockback_time = 0.4
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("crawl"):
		sprite.play("crawl")

func _perform_attack() -> void:
	# The bite lands through the shared contact check; the lunge sells it.
	velocity.x = _direction_to_player().x * chase_speed * 1.4
	sprite.speed_scale = 2.0
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_callback(func(): sprite.speed_scale = 1.0)
