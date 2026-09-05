extends EnemyBase
class_name BruteShaman

var is_swinging: bool = false

func _on_ready() -> void:
	detect_radius = 400.0
	attack_range = 100.0
	attack_cooldown = 2.5
	patrol_speed = 60.0
	chase_speed = 90.0
	max_health = 60
	contact_damage = 2
	knockback_speed = 300.0
	knockback_time = 0.7
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")

func _chase(delta: float) -> void:
	if is_swinging:
		velocity.x = 0
		return
	super._chase(delta)

func _perform_attack() -> void:
	is_swinging = true
	velocity.x = 0
	
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("windup"):
		sprite.play("windup")
		
	var t = create_tween()
	# Wind-up
	t.tween_interval(0.6)
	
	# Impact
	t.tween_callback(func():
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("impact"):
			sprite.play("impact")
		# Enable hit box or just lunge slightly
		velocity.x = _direction_to_player().x * 200.0
	)
	t.tween_interval(0.4)
	
	# Follow-through
	t.tween_callback(func():
		velocity.x = 0
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("follow_through"):
			sprite.play("follow_through")
	)
	t.tween_interval(0.4)
	
	# Finish
	t.tween_callback(func():
		is_swinging = false
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
			sprite.play("walk")
	)
