extends Node
## Autoloaded as "Progress". Tracks the rewards each boss hands over and lets the
## rest of the game ask "does the run have X yet" instead of passing flags around.
##
## - Boss 1 (Toy Cart)   -> lantern            : lets the player push back Level 2's dark
## - Boss 2 (The Horrid)  -> double_jump        : traversal upgrade
## - Boss 3 (Marionette)  -> extra_dash         : a second dash charge before landing
## - Boss 4 (Wind-Up Knight) -> vitality_boost  : +1 max HP

signal item_granted(item_id: String)

var _flags: Dictionary = {}

func grant(item_id: String) -> void:
	if _flags.get(item_id, false):
		return
	_flags[item_id] = true
	item_granted.emit(item_id)

func has(item_id: String) -> bool:
	return _flags.get(item_id, false)

## Full restart (new game), not a per-level retry.
func reset() -> void:
	_flags.clear()
