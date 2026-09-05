extends Node
## Autoloaded as "EffectPool".
##
## Recycles a fixed set of Sprite2D nodes for short-lived visual effects (landing
## dust, wall-slide sparks) so bursts of feedback never allocate during gameplay.
## Every effect is a one-shot fade+drift on a pooled sprite; when the pool is
## exhausted the oldest live effect is stolen rather than growing the pool.

const POOL_SIZE := 24

const TEXTURES := {
	"land": preload("res://assets/sprites/fx_frames/dust_land.png"),
	"walljump": preload("res://assets/sprites/fx_frames/dust_walljump.png"),
	"wallslide": preload("res://assets/sprites/fx_frames/dust_wallslide.png"),
}

var _pool: Array[Sprite2D] = []
var _next: int = 0
var _tweens: Array[Tween] = []
var _layer: Node2D

func _ready() -> void:
	_layer = Node2D.new()
	_layer.name = "EffectLayer"
	_layer.z_index = 5
	add_child(_layer)

	for i in POOL_SIZE:
		var s := Sprite2D.new()
		s.visible = false
		s.centered = true
		_layer.add_child(s)
		_pool.append(s)
		_tweens.append(null)

## Reparent the pool under the active level so effects inherit its transform and
## are removed together with it.
func attach_to(parent: Node) -> void:
	if _layer.get_parent() == parent:
		return
	_layer.get_parent().remove_child(_layer)
	parent.add_child(_layer)

func spawn(kind: String, world_pos: Vector2, flip_h: bool = false, scale_mult: float = 1.0, duration: float = 0.45) -> void:
	var tex: Texture2D = TEXTURES.get(kind)
	if tex == null:
		return

	var idx := _next
	_next = (_next + 1) % POOL_SIZE
	var s := _pool[idx]

	if _tweens[idx] != null and _tweens[idx].is_valid():
		_tweens[idx].kill()

	s.texture = tex
	s.global_position = world_pos
	s.flip_h = flip_h
	s.rotation = 0.0
	s.scale = Vector2.ONE * scale_mult
	s.modulate = Color(1, 1, 1, 0.9)
	s.visible = true

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(s, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	t.tween_property(s, "scale", s.scale * 1.35, duration).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "position:y", s.position.y - 6.0 * scale_mult, duration)
	t.chain().tween_callback(func(): s.visible = false)
	_tweens[idx] = t
