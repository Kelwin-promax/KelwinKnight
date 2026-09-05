extends CharacterBody2D
class_name Player

signal health_changed(current: int, maximum: int)
signal died

@export_group("Movement")
@export var SPEED: float = 260.0
@export var ACCELERATION: float = 2200.0      ## ground ramp-up, px/s^2
@export var FRICTION: float = 2600.0          ## ground ramp-down when no input
@export var AIR_ACCELERATION: float = 1400.0
@export var AIR_FRICTION: float = 600.0
@export var JUMP_VELOCITY: float = -560.0     ## ~105px apex against GRAVITY, which is what the ledge spacing assumes
@export var GRAVITY: float = 1500.0
@export var MAX_FALL_SPEED: float = 820.0
@export var WALL_SLIDE_SPEED: float = 130.0

@export_group("Abilities")
@export var DASH_SPEED: float = 640.0
@export var DASH_DURATION: float = 0.18
@export var ATTACK_DURATION: float = 0.32

@export_group("Survival")
@export var BASE_MAX_HEALTH: int = 3
@export var INVULNERABLE_TIME: float = 1.5
@export var KNOCKBACK_SPEED: float = 250.0
@export var KNOCKBACK_TIME: float = 0.5

const FLASH_TIME := 0.1
const BLINK_INTERVAL := 0.08                  ## intermittent white flash while invulnerable
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const TURN_SPEED_THRESHOLD := 90.0            ## below this a direction change isn't a skid

var MAX_HEALTH: int = 3
var health: int
var facing_right: bool = true

var _dash_timer: float = 0.0
var _can_dash: bool = true
var _dash_charges: int = 1                    ## Progress.extra_dash grants a 2nd air charge
var _attack_timer: float = 0.0
var _knockback_timer: float = 0.0
var _invuln_timer: float = 0.0
var _blink_timer: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = true
var _has_double_jumped: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var anim: AnimationManager = $AnimationManager
@onready var lantern: PointLight2D = $LanternLight

func _ready() -> void:
	add_to_group("player")
	MAX_HEALTH = BASE_MAX_HEALTH + (1 if Progress.has("vitality_boost") else 0)
	health = MAX_HEALTH
	health_changed.emit(health, MAX_HEALTH)
	lantern.enabled = Progress.has("lantern")
	Progress.item_granted.connect(_on_item_granted)

func _on_item_granted(item_id: String) -> void:
	if item_id == "lantern":
		lantern.enabled = true
	elif item_id == "vitality_boost":
		MAX_HEALTH += 1
		health += 1
		health_changed.emit(health, MAX_HEALTH)

func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if _knockback_timer > 0.0:
		_process_knockback(delta)
	elif _dash_timer > 0.0:
		_process_dash(delta)
	elif _attack_timer > 0.0:
		_process_attack(delta)
	else:
		_process_movement(delta)

	move_and_slide()
	_detect_landing()
	_update_animation()
	_update_invuln_blink(delta)

func _tick_timers(delta: float) -> void:
	_dash_timer = max(_dash_timer - delta, 0.0)
	_attack_timer = max(_attack_timer - delta, 0.0)
	_knockback_timer = max(_knockback_timer - delta, 0.0)
	_invuln_timer = max(_invuln_timer - delta, 0.0)
	_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)

	if is_on_floor():
		_coyote_timer = COYOTE_TIME
		_can_dash = true
		_dash_charges = 2 if Progress.has("extra_dash") else 1
		_has_double_jumped = false
	else:
		_coyote_timer = max(_coyote_timer - delta, 0.0)

	# Edge-triggered, so holding the key does not re-arm the jump.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER

# ---------------------------------------------------------------- movement ----

func _process_movement(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	_apply_gravity(delta, direction)
	_apply_horizontal(delta, direction)

	if _jump_buffer_timer > 0.0:
		_try_jump()

	if Input.is_action_just_pressed("attack") and is_on_floor():
		_attack_timer = ATTACK_DURATION
		anim.request(AnimationManager.State.COMBAT, true)

	if Input.is_action_just_pressed("dash") and _dash_charges > 0:
		_dash_timer = DASH_DURATION
		_dash_charges -= 1

func _apply_gravity(delta: float, direction: float) -> void:
	if is_on_floor():
		return
	if _is_wall_sliding(direction):
		velocity.y = min(velocity.y + GRAVITY * delta, WALL_SLIDE_SPEED)
		if Engine.get_physics_frames() % 10 == 0:
			EffectPool.spawn("wallslide", global_position + Vector2(_wall_side() * 18.0, 10.0), _wall_side() < 0, 0.5)
	else:
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

## Ramps toward the target speed instead of snapping to it, so releasing one
## direction key and pressing the other carries the existing momentum through.
func _apply_horizontal(delta: float, direction: float) -> void:
	var grounded := is_on_floor()
	if is_zero_approx(direction):
		var drag := FRICTION if grounded else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0.0, drag * delta)
		return

	var accel := ACCELERATION if grounded else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, direction * SPEED, accel * delta)

	var turning_around := (direction > 0.0) != facing_right
	if turning_around:
		if grounded and absf(velocity.x) > TURN_SPEED_THRESHOLD:
			anim.request(AnimationManager.State.TURNING, true)
		facing_right = direction > 0.0

func _try_jump() -> void:
	if _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
	elif is_on_wall_only():
		var normal := get_wall_normal()
		velocity.y = JUMP_VELOCITY
		velocity.x = normal.x * SPEED
		facing_right = normal.x > 0.0
		_jump_buffer_timer = 0.0
		EffectPool.spawn("walljump", global_position + Vector2(-normal.x * 18.0, 0.0), normal.x > 0.0, 0.6)
	elif Progress.has("double_jump") and not _has_double_jumped:
		velocity.y = JUMP_VELOCITY * 0.85
		_has_double_jumped = true
		_jump_buffer_timer = 0.0
		EffectPool.spawn("land", global_position + Vector2(0.0, 20.0), false, 0.4)

func _is_wall_sliding(direction: float) -> bool:
	if is_on_floor() or not is_on_wall_only() or velocity.y <= 0.0:
		return false
	return not is_zero_approx(direction) and signf(direction) == -signf(get_wall_normal().x)

func _wall_side() -> float:
	return -signf(get_wall_normal().x)

# ------------------------------------------------------------- ability states --

func _process_dash(_delta: float) -> void:
	velocity = Vector2((DASH_SPEED if facing_right else -DASH_SPEED), 0.0)

func _process_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

func _process_knockback(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, AIR_FRICTION * delta)
	velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

## True while a dash is active -- bosses whose grab/parry the spec calls out as
## dash-escapable check this instead of duplicating dash state.
func is_dashing() -> bool:
	return _dash_timer > 0.0

func is_invulnerable() -> bool:
	return _invuln_timer > 0.0

# ----------------------------------------------------------------- feedback ---

func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if _invuln_timer > 0.0 or _dash_timer > 0.0:
		return

	health = max(health - amount, 0)
	health_changed.emit(health, MAX_HEALTH)

	_invuln_timer = INVULNERABLE_TIME
	_blink_timer = 0.0
	_knockback_timer = KNOCKBACK_TIME
	var away := 1.0 if source_position == Vector2.ZERO else signf(global_position.x - source_position.x)
	if is_zero_approx(away):
		away = -1.0 if facing_right else 1.0
	velocity = Vector2(away * KNOCKBACK_SPEED, JUMP_VELOCITY * 0.45)

	anim.request(AnimationManager.State.KNOCKBACK, true)
	_flash()

	if health == 0:
		died.emit()
		LevelLoader.reload_current_level()

func heal(amount: int) -> void:
	if health > 0 and health < MAX_HEALTH:
		health = min(health + amount, MAX_HEALTH)
		health_changed.emit(health, MAX_HEALTH)

func _flash() -> void:
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_amount", 1.0)
	var t := create_tween()
	t.tween_interval(FLASH_TIME)
	t.tween_callback(func(): mat.set_shader_parameter("flash_amount", 0.0))

## Intermittent blink for the rest of the invulnerability window, distinct from the
## single bright hit-flash above.
func _update_invuln_blink(delta: float) -> void:
	if _invuln_timer <= 0.0:
		sprite.visible = true
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = BLINK_INTERVAL
		sprite.visible = not sprite.visible

func _detect_landing() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		EffectPool.spawn("land", global_position + Vector2(0.0, 56.0), false, 0.55)
	_was_on_floor = grounded

# ---------------------------------------------------------------- animation ---

func _update_animation() -> void:
	anim.set_facing(facing_right)

	if _knockback_timer > 0.0:
		return
	if _dash_timer > 0.0:
		anim.request(AnimationManager.State.DASHING)
		return
	if _attack_timer > 0.0:
		return

	if not is_on_floor():
		if _is_wall_sliding(Input.get_axis("move_left", "move_right")):
			anim.request(AnimationManager.State.WALLSLIDE)
		elif velocity.y < 0.0:
			anim.request(AnimationManager.State.JUMPING)
		else:
			anim.request(AnimationManager.State.FALLING)
	elif absf(velocity.x) > 12.0:
		anim.request(AnimationManager.State.WALKING)
	else:
		anim.request(AnimationManager.State.IDLE)
