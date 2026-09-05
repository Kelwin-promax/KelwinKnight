extends EnemyBase
class_name Exploder

var is_grabbing: bool = false
var grab_timer: float = 0.0
var grab_duration: float = 0.8
var explosion_radius: float = 150.0

func _on_ready() -> void:
	detect_radius = 400.0
	attack_range = 80.0
	attack_cooldown = 3.0
	patrol_speed = 60.0
	chase_speed = 120.0
	max_health = 35
	contact_damage = 0 # Deals damage on explosion instead
	knockback_speed = 300.0
	knockback_time = 0.6
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")

func _physics_process(delta: float) -> void:
	if is_grabbing:
		velocity = Vector2.ZERO
		grab_timer -= delta
		if player != null and is_instance_valid(player):
			player.global_position = global_position # Hold player
		if grab_timer <= 0.0:
			_explode()
		return
		
	super._physics_process(delta)

func _perform_attack() -> void:
	is_grabbing = true
	grab_timer = grab_duration

func _explode() -> void:
	is_grabbing = false
	if player != null and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		if dist <= explosion_radius:
			if player.has_method("take_damage"):
				player.take_damage(2, global_position)
	
	_die()
