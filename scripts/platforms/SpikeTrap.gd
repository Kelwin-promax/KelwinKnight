extends Area2D
class_name SpikeTrap
## A 12px-tall damage strip. The hurtbox is deliberately shorter than the sprite so
## brushing the tips while jumping past does not register as a hit.

@export var damage: int = 1
@export var width: float = 48.0

const HURT_HEIGHT := 12.0

@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, HURT_HEIGHT)
	collision.shape = shape
	collision.position = Vector2(0.0, -HURT_HEIGHT * 0.5)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.take_damage(damage, global_position)
