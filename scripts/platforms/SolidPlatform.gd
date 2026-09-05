@tool
extends StaticBody2D
class_name SolidPlatform
## A static block of arbitrary size that builds its own collider and 32px stone
## tiling from `size`, so laying out a room is a matter of dropping instances and
## typing a width rather than hand-editing a shape per platform.

const TILE := preload("res://assets/sprites/stage/stone_tile_32.png")
const TILE_SIZE := 32.0

@export var size: Vector2 = Vector2(192.0, 32.0):
	set(value):
		size = value
		_rebuild()

var _collision: CollisionShape2D
var _visual: TextureRect

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return

	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.shape = RectangleShape2D.new()
		add_child(_collision)
	if _visual == null:
		_visual = TextureRect.new()
		_visual.texture = TILE
		_visual.stretch_mode = TextureRect.STRETCH_TILE
		_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_visual)

	# Snap to whole tiles so the stone pattern never ends mid-block.
	var tiled := Vector2(
		max(round(size.x / TILE_SIZE), 1.0) * TILE_SIZE,
		max(round(size.y / TILE_SIZE), 1.0) * TILE_SIZE
	)

	(_collision.shape as RectangleShape2D).size = tiled
	_visual.position = -tiled * 0.5
	_visual.size = tiled
