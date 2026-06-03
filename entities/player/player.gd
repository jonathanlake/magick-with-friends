class_name Player
extends RigidBody3D

@export var move_force: float = 40.0
@export var max_speed: float = 8.0
@export var ground_friction: float = 8.0
@export var jump_force: float = 7.0
@export var jump_stamina_cost: float = 10.0
@export var jump_gravity_multiplier: float = 2.5   # extra gravity while rising
@export var fall_gravity_multiplier: float = 3.0   # extra gravity while falling
@export var climb_force: float = 25.0
@export var wall_stick_force: float = 8.0
@export var climb_friction: float = 12.0
@export var climb_drain_rate: float = 12.0  # stamina per second while holding grab
@export var grip_loss_cooldown: float = 0.5
@export var lunge_force: float = 9.0
@export var lunge_stamina_cost: float = 25.0
@export var mantle_impulse: float = 7.0
@export var mantle_velocity_threshold: float = 0.3
@export var mantle_step_height: float = 0.9
@export var camera_height: float = 0.75
@export var camera_smoothing: float = 15.0
@export var mouse_sensitivity: float = 0.003

# Set by the spawner before _enter_tree. Must be applied in _enter_tree (not _ready)
# so MultiplayerSynchronizer children register with the correct authority on tree entry.
var input_multiplayer_authority: int = 1
var player_name: String = ""

@onready var _input_sync: PlayerInputSynchronizerComponent = $PlayerInputSynchronizerComponent
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _name_label: Label3D = $NameLabel
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _ground_check: RayCast3D = $GroundCheck
@onready var _stamina: StaminaComponent = $StaminaComponent

var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0
var _prev_jump_pressed: bool = false
var _jump_queued: bool = false
var _is_climbing: bool = false
var _wall_detected: bool = false
var _climb_normal: Vector3 = Vector3.ZERO
var _prev_sprint_pressed: bool = false
var _lunge_queued: bool = false
var _mantle_queued: bool = false
var _grip_cooldown: float = 0.0
var _wand: WandComponent
var _dead: bool = false


func _enter_tree() -> void:
	set_multiplayer_authority(input_multiplayer_authority)


func _ready() -> void:
	_name_label.text = player_name

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
	_stamina.depleted.connect(_on_stamina_depleted)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
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

	if _grip_cooldown > 0.0:
		_grip_cooldown -= delta

	_detect_wall()

	# Rising-edge detection for jump.
	var jump_now := _input_sync.is_jump_pressed
	if jump_now and not _prev_jump_pressed:
		_jump_queued = true
	_prev_jump_pressed = jump_now

	# Rising-edge detection for lunge (sprint while climbing).
	var sprint_now := _input_sync.is_sprint_pressed
	if sprint_now and not _prev_sprint_pressed and _is_climbing:
		_lunge_queued = true
	_prev_sprint_pressed = sprint_now

	# Regen primary stamina when grounded and not climbing.
	if _ground_check.is_colliding() and not _is_climbing:
		_stamina.regen(delta)

	# Cast: read locally on the authority peer; the wand gates by its own cooldown.
	if _wand and Input.is_action_pressed("cast") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var aim := -_camera.global_transform.basis.z
		_wand.try_cast(_camera.global_position + aim * 0.6, aim)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_multiplayer_authority():
		return
	if _dead:
		return

	if _is_climbing:
		_integrate_climbing(state)
	else:
		_integrate_movement(state)


func _integrate_climbing(state: PhysicsDirectBodyState3D) -> void:
	# Cancel gravity so the player hangs on the surface.
	state.apply_central_force(-state.total_gravity * mass)

	# Stick toward the surface.
	state.apply_central_force(-_climb_normal * wall_stick_force)

	# Damp velocity — climbing has its own tighter friction.
	var vel := state.linear_velocity
	var damp := maxf(0.0, 1.0 - climb_friction * state.step)
	state.linear_velocity = vel * damp

	# Project WASD onto the surface plane.
	# Wall-up: world up projected onto surface so W/S drives vertical travel.
	# Wall-rt: camera right projected onto surface so A/D slides laterally.
	var input_dir := _input_sync.movement_vector
	if input_dir != Vector2.ZERO:
		var wall_up := (Vector3.UP - _climb_normal * _climb_normal.dot(Vector3.UP)).normalized()
		var cam_rt := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
		var wall_rt := (cam_rt - _climb_normal * _climb_normal.dot(cam_rt)).normalized()
		if not wall_up.is_zero_approx() and not wall_rt.is_zero_approx():
			var dir := (wall_up * (-input_dir.y) + wall_rt * input_dir.x).normalized()
			state.apply_central_force(dir * climb_force)

	_stamina.drain(climb_drain_rate * state.step)

	if _lunge_queued:
		# Lunge away from the wall and upward — can chain into a jump on landing.
		var lunge_dir := (-_climb_normal + Vector3.UP * 0.5).normalized()
		state.apply_central_impulse(lunge_dir * lunge_force)
		_stamina.drain(lunge_stamina_cost)
		_lunge_queued = false


func _integrate_movement(state: PhysicsDirectBodyState3D) -> void:
	# Horizontal-only friction — Y axis left free for gravity and jumps.
	var vel := state.linear_velocity
	var friction := maxf(0.0, 1.0 - ground_friction * state.step)
	state.linear_velocity = Vector3(vel.x * friction, vel.y, vel.z * friction)

	if _jump_queued and _ground_check.is_colliding():
		state.apply_central_impulse(Vector3.UP * jump_force)
		_stamina.drain(jump_stamina_cost)
		_jump_queued = false

	if _mantle_queued:
		# Nudge up to clear the ledge corner, then push forward onto the surface.
		# Cap upward velocity so a fast climb doesn't overshoot narrow ledges.
		state.transform.origin.y += mantle_step_height
		state.linear_velocity.y = clamp(state.linear_velocity.y, 0.0, 3.0)
		state.apply_central_impulse(-_climb_normal * mantle_impulse)
		_mantle_queued = false

	# Asymmetric gravity: snappier rise, weightier fall.
	if not _ground_check.is_colliding():
		if state.linear_velocity.y > 0.0:
			state.apply_central_force(state.total_gravity * mass * (jump_gravity_multiplier - 1.0))
		elif state.linear_velocity.y < 0.0:
			state.apply_central_force(state.total_gravity * mass * (fall_gravity_multiplier - 1.0))

	if _grip_cooldown > 0.0:
		return

	var input_dir := _input_sync.movement_vector
	if input_dir == Vector2.ZERO:
		return

	var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
	var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var move_dir := (forward * (-input_dir.y) + right * input_dir.x).normalized()

	var hspeed := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z).length()
	if hspeed < max_speed:
		state.apply_central_force(move_dir * move_force)


func _detect_wall() -> void:
	# Climbing/parkour is cut for the slice (LMB is now Cast). Kept as a no-op so the
	# controller and the dev HUD's climb references stay valid.
	_wall_detected = false
	_is_climbing = false


func _on_stamina_depleted() -> void:
	_grip_cooldown = grip_loss_cooldown
	_is_climbing = false


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
