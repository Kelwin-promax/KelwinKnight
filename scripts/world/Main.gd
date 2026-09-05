extends Node2D
## Composition root: boots Level 1, advances through the 5 stages and the Goliath
## arena on each boss death, and wraps every swap in a 1s fade to black.
##
## Contract each level scene must honour: a node named "Boss" (any EnemyBase whose
## death should open the way forward) and/or a node named "LevelExit" (an Area2D
## the player can just walk into, for the stage-5 -> Goliath handoff where there is
## no in-room boss to kill).

const FADE_TIME := 1.0

@onready var level_host: Node2D = $LevelHost
@onready var fade: ColorRect = $FadeLayer/Fade
@onready var victory_layer: CanvasLayer = $VictoryLayer
@onready var victory_label: Label = $VictoryLayer/VictoryLabel

func _ready() -> void:
	victory_layer.hide()
	fade.color.a = 1.0
	LevelLoader.level_loaded.connect(_on_level_loaded)
	LevelLoader.load_level(1, level_host)
	await get_tree().process_frame
	_fade(0.0)

func _on_level_loaded(_level_id: int, node: Node) -> void:
	var boss := node.get_node_or_null("Boss")
	if boss and boss.has_signal("died"):
		boss.died.connect(_on_boss_defeated)

	var exit := node.get_node_or_null("LevelExit")
	if exit and exit.has_signal("body_entered"):
		exit.body_entered.connect(_on_level_exit_reached)

func _on_boss_defeated(_boss) -> void:
	if LevelLoader.is_final_level():
		_show_victory()
		return
	_advance_after_delay()

func _on_level_exit_reached(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_advance_after_delay()

func _advance_after_delay() -> void:
	await get_tree().create_timer(1.0).timeout
	await _fade(1.0)
	LevelLoader.advance_level()
	await get_tree().process_frame
	await _fade(0.0)

func _fade(target_alpha: float) -> void:
	var t := create_tween()
	t.tween_property(fade, "color:a", target_alpha, FADE_TIME)
	await t.finished

func _show_victory() -> void:
	await get_tree().create_timer(1.5).timeout
	await _fade(1.0)
	victory_layer.show()
	await _fade(0.0)
