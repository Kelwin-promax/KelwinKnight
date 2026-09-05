extends CharacterBody2D
class_name EnemyBase
## Shared brain for every creature: sense the player, chase, strike, take a hit.
##
## Subclasses supply movement and the actual attack by overriding `_patrol`,
## `_chase` and `_perform_attack`; everything about health, aggro, knockback and
## death is handled here so the roster stays consistent.

signal died(enemy: EnemyBase)

enum State { PATROL, CHASE, ATTACK, HURT, DEAD }

@export_group("Senses")
@export var detect_radius: float = 300.0
@export var attack_range: float = 60.0     ## how far away _perform_attack() can trigger from
@export var attack_cooldown: float = 1.2
## How close the player has to be to take passive touch damage -- kept separate from
## attack_range because ranged attackers set that huge to "notice" the player from
## across the room, which must not also mean "zaps on proximity alone".
@export var contact_range: float = 55.0

@export_group("Movement")
@export var patrol_speed: float = 80.0
@export var chase_speed: float = 150.0
@export var patrol_range: float = 180.0
@export var gravity: float = 1500.0
@export var affected_by_gravity: bool = true

@export_group("Combat")
@export var max_health: int = 20
@export var contact_damage: int = 1
@export var knockback_speed: float = 150.0
@export var knockback_time: float = 0.4

const HIT_FLASH_TIME := 0.09
const DEATH_FADE := 0.35

var health: int
var state: State = State.PATROL
var facing_right: bool = true
var origin_x: float = 0.0
var time_alive: float = 0.0

var _attack_timer: float = 0.0
var _hurt_timer: float = 0.0
var player: Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

## Which stage this instance was placed in (1-5). Drives the "+15% HP / +10% speed /
## +20% knockback / -0.2s cooldown per stage" escalation -- set this per level in the
## scene file instead of calling set_phase() from code.
@export var level_phase: int = 1

func _ready() -> void:
	health = max_health
	origin_x = global_position.x
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")
	_on_ready()
	_store_base_stats()
	set_phase(level_phase)

var base_max_health: int
var base_patrol_speed: float
var base_chase_speed: float
var base_knockback_speed: float
var base_attack_cooldown: float

func _store_base_stats() -> void:
	base_max_health = max_health
	base_patrol_speed = patrol_speed
	base_chase_speed = chase_speed
	base_knockback_speed = knockback_speed
	base_attack_cooldown = attack_cooldown
	health = max_health

func set_phase(phase: int) -> void:
	var p := float(max(1, phase) - 1)
	max_health = int(base_max_health * (1.0 + 0.15 * p))
	health = max_health
	patrol_speed = base_patrol_speed * (1.0 + 0.10 * p)
	chase_speed = base_chase_speed * (1.0 + 0.10 * p)
	knockback_speed = base_knockback_speed * (1.0 + 0.20 * p)
	attack_cooldown = maxf(0.2, base_attack_cooldown - (0.2 * p))

## Subclass hook, runs after the base finishes setting up.
func _on_ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	time_alive += delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_hurt_timer = maxf(_hurt_timer - delta, 0.0)

	if state == State.DEAD:
		return

	if _hurt_timer > 0.0:
		state = State.HURT
		if affected_by_gravity and not is_on_floor():
			velocity.y += gravity * delta
	else:
		_think(delta)

	move_and_slide()
	_face_travel_direction()
	_touch_player()

func _think(delta: float) -> void:
	var target_distance := _distance_to_player()

	if target_distance <= attack_range and _attack_timer <= 0.0:
		state = State.ATTACK
		_attack_timer = attack_cooldown
		_perform_attack()
	elif target_distance <= detect_radius:
		state = State.CHASE
		_chase(delta)
	else:
		state = State.PATROL
		_patrol(delta)

func _distance_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)

func _direction_to_player() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.RIGHT
	return (player.global_position - global_position).normalized()

# ---------------------------------------------------------- subclass hooks ----

func _patrol(delta: float) -> void:
	_walk_between_bounds(patrol_speed, delta)

func _chase(delta: float) -> void:
	_walk_between_bounds(chase_speed, delta, true)

func _perform_attack() -> void:
	pass

func _on_death() -> void:
	pass

# --------------------------------------------------------------- behaviour ----

## Ground movement shared by the walking enemies: bounce off walls and stay inside
## `patrol_range` of the spot the enemy was placed at.
func _walk_between_bounds(speed: float, delta: float, toward_player: bool = false) -> void:
	if affected_by_gravity and not is_on_floor():
		velocity.y += gravity * delta

	if toward_player:
		velocity.x = _direction_to_player().x * speed
	else:
		if is_zero_approx(velocity.x):
			velocity.x = speed
		if is_on_wall():
			velocity.x = -velocity.x
		if global_position.x > origin_x + patrol_range:
			velocity.x = -speed
		elif global_position.x < origin_x - patrol_range:
			velocity.x = speed

func _face_travel_direction() -> void:
	if absf(velocity.x) > 4.0:
		facing_right = velocity.x > 0.0
	if sprite:
		sprite.flip_h = not facing_right

## Enemies hurt the player by touching them; the player's own invulnerability
## window keeps this from draining health every frame.
func _touch_player() -> void:
	if contact_damage <= 0 or player == null or not is_instance_valid(player):
		return
	if _distance_to_player() > contact_range:
		return
	if player.has_method("take_damage"):
		player.take_damage(contact_damage, global_position)

# ------------------------------------------------------------------ damage ----

func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEAD:
		return

	health -= amount
	_flash()

	var away := signf(global_position.x - source_position.x)
	if is_zero_approx(away):
		away = -1.0 if facing_right else 1.0
	velocity.x = away * knockback_speed
	if affected_by_gravity:
		velocity.y = -knockback_speed * 0.45
	_hurt_timer = knockback_time

	# Being hit is what wakes a distant enemy up.
	detect_radius = maxf(detect_radius, _distance_to_player() + 50.0)

	if health <= 0:
		_die()

func _flash() -> void:
	if sprite == null:
		return
	sprite.modulate = Color(3.0, 3.0, 3.0)
	var t := create_tween()
	t.tween_interval(HIT_FLASH_TIME)
	t.tween_callback(func(): sprite.modulate = Color.WHITE)

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_on_death()
	died.emit(self)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE)
	t.tween_property(sprite, "scale", sprite.scale * 1.15, DEATH_FADE)
	t.chain().tween_callback(queue_free)
