extends StaticBody2D
class_name FragilePlatform
## Crumbles a fixed moment after anything stands on it, then rebuilds itself so the
## room stays playable on a second pass. The three sprite stages come straight from
## the stage sheet: intact, cracking, collapsed.

@export var crumble_delay: float = 0.5
@export var respawn_delay: float = 3.0

const STAGE_TEXTURES := [
	preload("res://assets/sprites/stage/fragile_0.png"),
	preload("res://assets/sprites/stage/fragile_1.png"),
	preload("res://assets/sprites/stage/fragile_2.png"),
]

var _triggered: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var detector: Area2D = $StandDetector

func _ready() -> void:
	sprite.texture = STAGE_TEXTURES[0]
	detector.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body is Player:
		return
	_triggered = true
	_crumble()

func _crumble() -> void:
	var t := create_tween()
	t.tween_interval(crumble_delay * 0.5)
	t.tween_callback(func(): sprite.texture = STAGE_TEXTURES[1])
	# A short shudder telegraphs the collapse before the floor actually leaves.
	t.tween_property(sprite, "position:x", 2.0, 0.06).as_relative()
	t.tween_property(sprite, "position:x", -4.0, 0.06).as_relative()
	t.tween_property(sprite, "position:x", 2.0, 0.06).as_relative()
	t.tween_interval(max(crumble_delay * 0.5 - 0.18, 0.0))
	t.tween_callback(_collapse)

func _collapse() -> void:
	sprite.texture = STAGE_TEXTURES[2]
	collision.set_deferred("disabled", true)
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 0.0, 0.25)
	t.tween_interval(respawn_delay)
	t.tween_callback(_restore)

func _restore() -> void:
	sprite.texture = STAGE_TEXTURES[0]
	collision.set_deferred("disabled", false)
	create_tween().tween_property(sprite, "modulate:a", 1.0, 0.2)
	_triggered = false
