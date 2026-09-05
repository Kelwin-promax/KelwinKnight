extends Area2D
class_name Projectile
## One pooled hazard bolt. `ProjectilePool` recycles a fixed set of these instead of
## instancing a new node per shot, per the "sprite pooling" requirement.

var velocity: Vector2 = Vector2.ZERO
var damage: int = 1
var knockback_speed: float = 200.0
var lifetime: float = 3.0
var fall_accel: float = 0.0          ## 0 = straight line; >0 lets bosses lob arcs
var hit_players: bool = true      ## enemy bolts hit the player; set false to hurt enemies instead
var spin_speed: float = 0.0

var _age: float = 0.0
var _active: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	set_physics_process(false)

## Pulled from the pool and dropped into the world. `visual` picks the sprite so one
## pooled shape can be reused for every enemy's bolt.
func fire(from: Vector2, dir: Vector2, speed: float, visual: Texture2D, dmg: int = 1) -> void:
	global_position = from
	velocity = dir.normalized() * speed
	damage = dmg
	sprite.texture = visual
	sprite.rotation = velocity.angle()
	_age = 0.0
	_active = true
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if fall_accel > 0.0:
		velocity.y += fall_accel * delta
	global_position += velocity * delta
	if spin_speed != 0.0:
		sprite.rotation += spin_speed * delta
	elif fall_accel > 0.0:
		sprite.rotation = velocity.angle()
	if _age >= lifetime:
		_deactivate()

func _on_body_entered(body: Node2D) -> void:
	_resolve_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_resolve_hit(area)

func _resolve_hit(target: Node) -> void:
	if not _active:
		return
	var is_player_target := target.is_in_group("player")
	var is_enemy_target := target.is_in_group("enemies")

	if hit_players and is_player_target and target.has_method("take_damage"):
		target.take_damage(damage, global_position)
		_deactivate()
	elif not hit_players and is_enemy_target and target.has_method("take_damage"):
		target.take_damage(damage, global_position)
		_deactivate()
	elif not is_player_target and not is_enemy_target and target is PhysicsBody2D:
		_deactivate() # hit the scenery

func _deactivate() -> void:
	_active = false
	visible = false
	# body_entered/area_entered are physics-server signals; toggling monitoring from
	# inside their callback is rejected unless deferred (_resolve_hit is always
	# called from one of those two signals or from the same-frame lifetime check).
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)
	velocity = Vector2.ZERO
