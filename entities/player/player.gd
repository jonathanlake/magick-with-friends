class_name Player
extends RigidBody3D

# friction-terminal speed = move_force / ground_friction = 15 u/s, above max_speed, so max_speed
# is the real binding cap (reached snappily). ~12 u/s ≈ the prior feel and ~3× the 4 u/s enemy
# speed, so players can kite the horde.
@export var move_force: float = 120.0
@export var max_speed: float = 12.0
@export var ground_friction: float = 8.0
@export var jump_force: float = 7.0
@export var jump_gravity_multiplier: float = 2.5   # extra gravity while rising
@export var fall_gravity_multiplier: float = 3.0   # extra gravity while falling
@export var camera_height: float = 0.75
@export var camera_smoothing: float = 15.0
@export var mouse_sensitivity: float = 0.003

# Set by the spawner before _enter_tree. Must be applied in _enter_tree (not _ready)
# so MultiplayerSynchronizer children register with the correct authority on tree entry.
var input_multiplayer_authority: int = 1
var player_name: String = ""
# This player's owning peer id, set by the spawner. Used to route host-authoritative damage
# without parsing it back out of the node name (the node IS named str(peer_id), but the reverse
# parse silently yields 0 for any non-numeric name).
var peer_id: int = 1

@onready var _input_sync: PlayerInputSynchronizerComponent = $PlayerInputSynchronizerComponent
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _name_label: Label3D = $NameLabel
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _ground_check: RayCast3D = $GroundCheck

var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0
var _prev_jump_pressed: bool = false
var _jump_queued: bool = false
var _wand: WandComponent
var _dead: bool = false


func _enter_tree() -> void:
	set_multiplayer_authority(input_multiplayer_authority)


func _ready() -> void:
	_name_label.text = player_name
	# Join the "players" group on every peer so enemy AI can find players via the group
	# instead of scanning all of Main's children + casting each one every physics frame.
	add_to_group("players")

	# Log the authority assigned to this copy (debug sessions only). Before the authority
	# early-return below, so it also reports REMOTE player copies — which is the point: it lets a
	# two-window run prove per-peer authority actually propagated to clients.
	_log_authority_if_debug()

	# Wand on every peer's copy (same node path) so RPC cast requests route to the host.
	_wand = WandComponent.new()
	_wand.name = "WandComponent"
	add_child(_wand)

	if not is_multiplayer_authority():
		_camera.current = false
		return

	_camera.current = true
	_name_label.visible = false
	_mesh.visible = false
	_camera_rig.global_position = global_position + Vector3(0.0, camera_height, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if GameManager.console_open:
		return  # dev console focused — don't look / re-capture the mouse
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw -= event.relative.x * mouse_sensitivity
		_camera_pitch -= event.relative.y * mouse_sensitivity
		_camera_pitch = clamp(_camera_pitch, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var target := global_position + Vector3(0.0, camera_height, 0.0)
	_camera_rig.global_position = _camera_rig.global_position.lerp(target, camera_smoothing * delta)
	_camera_rig.global_rotation.y = _camera_yaw
	_camera.rotation.x = _camera_pitch

	if _dead:
		return

	# Rising-edge detection for jump.
	var jump_now := _input_sync.is_jump_pressed
	if jump_now and not _prev_jump_pressed:
		_jump_queued = true
	_prev_jump_pressed = jump_now

	# Cast: read locally on the authority peer; the wand gates by its own cooldown.
	if _wand and Input.is_action_pressed("cast") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var aim := -_camera.global_transform.basis.z
		_wand.try_cast(_camera.global_position + aim * 0.6, aim)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_multiplayer_authority():
		return
	if _dead:
		return

	# Horizontal-only friction — Y axis left free for gravity and jumps.
	var vel := state.linear_velocity
	var friction := maxf(0.0, 1.0 - ground_friction * state.step)
	state.linear_velocity = Vector3(vel.x * friction, vel.y, vel.z * friction)

	if _jump_queued and _ground_check.is_colliding():
		state.apply_central_impulse(Vector3.UP * jump_force)
		_jump_queued = false

	# Asymmetric gravity: snappier rise, weightier fall.
	if not _ground_check.is_colliding():
		if state.linear_velocity.y > 0.0:
			state.apply_central_force(state.total_gravity * mass * (jump_gravity_multiplier - 1.0))
		elif state.linear_velocity.y < 0.0:
			state.apply_central_force(state.total_gravity * mass * (fall_gravity_multiplier - 1.0))

	var input_dir := _input_sync.movement_vector
	if input_dir == Vector2.ZERO:
		return

	var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
	var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var move_dir := (forward * (-input_dir.y) + right * input_dir.x).normalized()

	var hspeed := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z).length()
	if hspeed < max_speed:
		state.apply_central_force(move_dir * move_force)


## Toggled by Main on death / respawn. Hides + freezes the body and gates input.
func set_dead(dead: bool) -> void:
	_dead = dead
	freeze = dead
	if dead:
		_mesh.visible = false
		_name_label.visible = false
	else:
		# Remote players show their mesh + name; the local first-person player keeps both hidden.
		_mesh.visible = not is_multiplayer_authority()
		_name_label.visible = not is_multiplayer_authority()


func is_dead() -> bool:
	return _dead


# Debug-only authority probe. Gated on the DEBUG autoload existing (it's disabled by default, no
# `*`, so this is silent in normal play and exported builds — it only fires during a two-window
# `debug_autostart` session). Prints, from THIS peer's view, what authority each player copy got.
func _log_authority_if_debug() -> void:
	if get_node_or_null("/root/DEBUG") == null:
		return
	print("[AUTH] peer %d sees Player '%s': authority=%d is_mine=%s" % [
		multiplayer.get_unique_id(), name, get_multiplayer_authority(), is_multiplayer_authority()])
