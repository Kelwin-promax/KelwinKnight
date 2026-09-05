extends Node
## Autoloaded as "ProjectilePool". Recycles a fixed set of Projectile nodes across
## every spitter, boss and future ranged attacker so combat-heavy rooms (Level 4-5,
## the Goliath's projectile walls) never instance-and-free during play.

const POOL_SIZE := 28
const PROJECTILE_SCENE := preload("res://scenes/fx/Projectile.tscn")

var _pool: Array[Projectile] = []
var _next: int = 0
var _layer: Node2D

func _ready() -> void:
	_layer = Node2D.new()
	_layer.name = "ProjectileLayer"
	_layer.z_index = 4
	add_child(_layer)
	for i in POOL_SIZE:
		var p: Projectile = PROJECTILE_SCENE.instantiate()
		p.visible = false
		p.monitoring = false
		_layer.add_child(p)
		_pool.append(p)

func attach_to(parent: Node) -> void:
	if _layer.get_parent() == parent:
		return
	_layer.get_parent().remove_child(_layer)
	parent.add_child(_layer)

## Launch one bolt from the pool. Returns the projectile in case the caller wants to
## tweak it further (arcs, spin, enemy-targeting) before it starts moving.
func fire(from: Vector2, dir: Vector2, speed: float, visual: Texture2D, damage: int = 1,
		fall_accel: float = 0.0, hit_players: bool = true, spin_speed: float = 0.0) -> Projectile:
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.fall_accel = fall_accel
	p.hit_players = hit_players
	p.spin_speed = spin_speed
	p.fire(from, dir, speed, visual, damage)
	return p
