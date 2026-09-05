extends EnemyBase
class_name Harpy

var is_diving: bool = false
var climb_timer: float = 0.0

func _on_ready() -> void:
	detect_radius = 500.0
	attack_range = 300.0
	attack_cooldown = 3.0
	patrol_speed = 80.0
	chase_speed = 100.0
	max_health = 40
	contact_damage = 2
	knockback_speed = 250.0
	knockback_time = 0.5
	affected_by_gravity = false
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("fly"):
		sprite.play("fly")

func _chase(delta: float) -> void:
	if climb_timer > 0.0:
		climb_timer -= delta
		velocity = Vector2(0, -60.0)
		_face_travel_direction()
		return
		
	if is_diving:
		return # let the dive finish
		
	# Fly towards player above them
	if player != null and is_instance_valid(player):
		var target_pos = player.global_position + Vector2(0, -200)
		var dir = (target_pos - global_position).normalized()
		velocity = dir * chase_speed
		_face_travel_direction()

func _perform_attack() -> void:
	if climb_timer > 0.0:
		return
		
	is_diving = true
	var dir = _direction_to_player()
	dir.y = 1.0 # force downward dive
	velocity = dir.normalized() * 200.0
	
	var t = create_tween()
	t.tween_interval(1.0) # dive for 1s
	t.tween_callback(_end_dive)

func _end_dive() -> void:
	is_diving = false
	climb_timer = 3.0 # climb for 3s
