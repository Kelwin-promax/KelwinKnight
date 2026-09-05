extends AnimatableBody2D
class_name MovingPlatform
## Shuttles between its start point and start + `travel` at a constant speed.
##
## AnimatableBody2D (with sync_to_physics on in the scene) is what carries a rider
## along; a StaticBody2D moved by script would slide out from under the player.

@export var travel: Vector2 = Vector2(220.0, 0.0)
@export var speed: float = 60.0
@export var start_reversed: bool = false

var _origin: Vector2
var _progress: float = 0.0
var _direction: float = 1.0

func _ready() -> void:
	_origin = position
	if start_reversed:
		_progress = 1.0
		_direction = -1.0

func _physics_process(delta: float) -> void:
	var span := travel.length()
	if span <= 0.0:
		return

	_progress += _direction * (speed / span) * delta
	if _progress >= 1.0:
		_progress = 1.0
		_direction = -1.0
	elif _progress <= 0.0:
		_progress = 0.0
		_direction = 1.0

	position = _origin + travel * _progress
