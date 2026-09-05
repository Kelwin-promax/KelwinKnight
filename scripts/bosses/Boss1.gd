extends EnemyBase
class_name Boss1
## "The Toy Cart" -- Level 1's boss. No animated art exists for a racing cart, so it
## reuses the mechanical trolley from the stage sheet and sells its personality
## through motion: a wind-up shudder, then a full-speed charge the width of the
## arena, spinning out into a spray of debris wherever it slams into a wall.
## First boss, so the tell is generous and the arena is small and flat.

signal item_awarded(item_id: String)

const CHARGE_SPEED := 420.0
const REV_TIME := 0.5
const DEBRIS_TEXTURE := preload("res://assets/sprites/stage/debris_0.png")

enum CartState { REVVING, CHARGING }
var cart_state: CartState = CartState.REVVING
var rev_timer: float = REV_TIME
var charge_dir: float = 1.0

func _on_ready() -> void:
	detect_radius = 2000.0   # always "aware"; this fight is about the charge lane, not stealth
	attack_range = 70.0
	attack_cooldown = 1.0
	max_health = 45
	contact_damage = 1
	knockback_speed = 300.0
	knockback_time = 0.5
	affected_by_gravity = true

func _think(delta: float) -> void:
	# This boss ignores the usual patrol/chase/attack split -- it is always racing
	# its lane, whether the player is close or not.
	if not is_on_floor():
		velocity.y += gravity * delta

	if cart_state == CartState.REVVING:
		velocity.x = 0.0
		sprite.rotation = sin(time_alive * 40.0) * 0.05
		rev_timer -= delta
		if rev_timer <= 0.0:
			cart_state = CartState.CHARGING
			sprite.rotation = 0.0
	else:
		velocity.x = charge_dir * CHARGE_SPEED
		if global_position.x > origin_x + patrol_range:
			_spin_out(-1.0)
		elif global_position.x < origin_x - patrol_range:
			_spin_out(1.0)

func _spin_out(new_dir: float) -> void:
	charge_dir = new_dir
	cart_state = CartState.REVVING
	rev_timer = REV_TIME
	for i in range(3):
		var spread := (i - 1) * 0.4
		var dir := Vector2(new_dir, -0.6).rotated(spread).normalized()
		ProjectilePool.fire(global_position, dir, 260.0, DEBRIS_TEXTURE, 1, 900.0)

func _on_death() -> void:
	Progress.grant("lantern")
	item_awarded.emit("lantern")
