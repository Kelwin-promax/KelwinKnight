extends Node
## Autoloaded as "LevelLoader". Swaps the active level scene under a given parent,
## keeps the effect/projectile pools pointed at whatever is currently loaded, and
## remembers enough to reload just the current level on a player death (a death
## should retry the phase, not boot all the way back to Level 1).

signal level_loaded(level_id: int, node: Node)

const LEVEL_PATHS := {
	1: "res://scenes/levels/Level1.tscn",
	2: "res://scenes/levels/Level2.tscn",
	3: "res://scenes/levels/Level3.tscn",
	4: "res://scenes/levels/Level4.tscn",
	5: "res://scenes/levels/Level5.tscn",
	6: "res://scenes/bosses/GoliathArena.tscn",
}
const FINAL_LEVEL_ID := 6

var current_level_id: int = 0
var current_level_node: Node = null
var _host: Node = null

func load_level(level_id: int, parent: Node = null) -> Node:
	if not LEVEL_PATHS.has(level_id):
		push_error("LevelLoader: no level registered with id %d" % level_id)
		return null

	var scene: PackedScene = load(LEVEL_PATHS[level_id])
	if scene == null:
		push_error("LevelLoader: failed to load %s" % LEVEL_PATHS[level_id])
		return null

	_host = parent if parent != null else get_tree().current_scene
	if current_level_node and is_instance_valid(current_level_node):
		current_level_node.queue_free()

	current_level_node = scene.instantiate()
	_host.add_child(current_level_node)
	current_level_id = level_id
	EffectPool.attach_to(current_level_node)
	ProjectilePool.attach_to(current_level_node)
	level_loaded.emit(level_id, current_level_node)
	return current_level_node

func reload_current_level() -> Node:
	return load_level(current_level_id, _host)

func advance_level() -> Node:
	var next_id: int = current_level_id + 1
	if not LEVEL_PATHS.has(next_id):
		return null
	return load_level(next_id, _host)

func is_final_level() -> bool:
	return current_level_id == FINAL_LEVEL_ID
