extends Node
class_name AnimationManager
## Drives an AnimatedSprite2D from a gameplay state instead of from animation names.
##
## The owner pushes the state it is in every frame; this decides what should play.
## States listed in ONE_SHOT hold the sprite until their clip ends, so a request for
## `WALK` arriving mid-swing cannot cut the attack short. Ask `is_busy()` before
## acting on input that a locked animation should block.

enum State { IDLE, WALKING, JUMPING, FALLING, COMBAT, KNOCKBACK, WALLSLIDE, TURNING, DASHING }

const ANIMS := {
	State.IDLE: "idle",
	State.WALKING: "walk",
	State.JUMPING: "jump",
	State.FALLING: "fall",
	State.COMBAT: "attack",
	State.KNOCKBACK: "knockback",
	State.WALLSLIDE: "wallslide",
	State.TURNING: "turn",
	State.DASHING: "dash",
}

## Clips that own the sprite until they finish playing.
const ONE_SHOT := [State.COMBAT, State.KNOCKBACK, State.TURNING]

@export var sprite_path: NodePath = ^"../AnimatedSprite2D"

var state: State = State.IDLE
var _sprite: AnimatedSprite2D
var _locked_by: int = -1

func _ready() -> void:
	_sprite = get_node_or_null(sprite_path)
	if _sprite:
		_sprite.animation_finished.connect(_on_animation_finished)

func is_busy() -> bool:
	return _locked_by != -1

## Ask for a state. Ignored while a one-shot clip is still running unless `force`.
func request(next_state: State, force: bool = false) -> void:
	if _sprite == null:
		return
	if _locked_by != -1 and not force:
		return

	if force and _locked_by != -1:
		_locked_by = -1

	if next_state == state and _sprite.is_playing():
		return

	var anim: String = ANIMS.get(next_state, "idle")
	if not _sprite.sprite_frames or not _sprite.sprite_frames.has_animation(anim):
		return

	state = next_state
	if next_state in ONE_SHOT:
		_locked_by = next_state
	_sprite.play(anim)

func set_facing(facing_right: bool) -> void:
	if _sprite:
		_sprite.flip_h = not facing_right

func _on_animation_finished() -> void:
	_locked_by = -1
