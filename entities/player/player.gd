class_name Player
extends CharacterBody3D

# Velocity-model first-person controller. max_speed is the hard horizontal cap; acceleration /
# ground_deceleration are how fast we reach it / stop. ~6 u/s vs the 4 u/s enemy speed lets players
# kite the horde. Tune these in playtest.
@export var max_speed: float = 6.0
@export var acceleration: float = 60.0          # units/sec² toward the wish velocity
@export var ground_deceleration: float = 50.0   # units/sec² toward zero when no input
@export var jump_velocity: float = 6.0          # initial upward velocity on jump
@export var jump_gravity_multiplier: float = 2.5   # extra gravity while rising (snappier apex)
@export var fall_gravity_multiplier: float = 3.0   # extra gravity while falling (weightier landing)
@export var camera_height: float = 0.75
@export var camera_smoothing: float = 15.0
@export var mouse_sensitivity: float = 0.003
# Casts spawn at the staff muzzle but aim toward a point this far down the camera ray, so the shot
# converges on the crosshair instead of flying parallel to it (offset by the muzzle's position).
# Larger = flatter convergence; should comfortably exceed normal engagement range.
@export var cast_aim_distance: float = 100.0

# Set by the spawner before _enter_tree. Must be applied in _enter_tree (not _ready)
# so MultiplayerSynchronizer children register with the correct authority on tree entry.
var input_multiplayer_authority: int = 1
var player_name: String = ""
# This player's owning peer id, set by the spawner. Used to route host-authoritative damage
# without parsing it back out of the node name (the node IS named str(peer_id), but the reverse
# parse silently yields 0 for any non-numeric name).
var peer_id: int = 1
# Catalog indices for the dealt blend, set by the spawner (replicated, so identical on every peer).
var form_idx: int = 0
var element_idx: int = 0
# Replicated look-yaw (the player's aim direction). The owning peer writes it from the camera each
# frame; the player MultiplayerSynchronizer replicates it outward (see player.tscn) so remote copies
# can face the model where the player is actually looking. The body itself is never rotated (the
# camera handles look), so we rotate the Visual node by this instead.
var aim_yaw: float = 0.0
# Replicated look-pitch (camera up/down angle, radians). Same driver pattern as aim_yaw: the owning
# peer authors it, it replicates (mode 1), and every peer feeds it to the Visual's spine-pitch
# modifier so the model tilts its upper body to where the player is looking (legs stay planted).
var aim_pitch: float = 0.0
# Replicated planar speed (world units/sec), authored by the owning peer from its real velocity and
# synced outward (see player.tscn). The Visual's LocomotionAnimator blends idle<->run from THIS
# instead of differentiating position, so remote copies get a steady value rather than a stepped
# network snapshot (which sawtooths the blend — the staff jitter). See locomotion_animator.gd.
var anim_speed: float = 0.0

@onready var _input_sync: PlayerInputSynchronizerComponent = $PlayerInputSynchronizerComponent
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _name_label: Label3D = $NameLabel
# The visible body — an instance of player_visual.tscn (the model + animations). Hidden for the
# local first-person player; shown for remote copies so teammates see this player's body. Also
# rotated by aim_yaw so the model faces the look direction.
@onready var _visual: Node3D = $Visual

# Aim-raycast mask: world(1) + players(2) + enemies(4) = 7, so the crosshair ray hits whatever is
# actually there. (Raw collision-layer bits, per the named layers in project.godot.)
const _AIM_MASK := 7

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
	# Indices set before add_child so the wand builds the dealt blend from the catalog in _ready.
	_wand = WandComponent.new()
	_wand.name = "WandComponent"
	_wand.form_idx = form_idx
	_wand.element_idx = element_idx
	add_child(_wand)

	if not is_multiplayer_authority():
		_camera.current = false
		return

	_camera.current = true
	_name_label.visible = false
	_visual.visible = false
	_camera_rig.global_position = global_position + Vector3(0.0, camera_height, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# The cast gesture fires its bolt at the animation's release frame, not on input. Only the owner
	# spawns (remote copies play the gesture but have no listener here). See _on_cast_released.
	if _visual and _visual.has_signal("oneshot_released"):
		_visual.oneshot_released.connect(_on_cast_released)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if GameManager.console_open:
		return  # dev console focused — don't look / re-capture the mouse
	# Dev-only: cycle through all Form×Element blends (gated on the DEBUG autoload, so it never fires
	# in normal play / exported builds). Lets a solo tester feel all four without restarting.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_B and get_node_or_null("/root/DEBUG") != null:
		_cycle_debug_spell()
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
		# Remote copy: orient the visible model to the replicated look-yaw (body is angular-locked),
		# feed it the replicated speed (steady value -> no remote blend jitter), and the replicated
		# look-pitch so the upper body tilts to where this player is aiming.
		if _visual:
			_visual.rotation.y = aim_yaw
			if _visual.has_method("feed_speed"):
				_visual.feed_speed(anim_speed)
			if _visual.has_method("feed_pitch"):
				_visual.feed_pitch(aim_pitch)
		return

	var target := global_position + Vector3(0.0, camera_height, 0.0)
	_camera_rig.global_position = _camera_rig.global_position.lerp(target, camera_smoothing * delta)
	_camera_rig.global_rotation.y = _camera_yaw
	_camera.rotation.x = _camera_pitch

	# Publish our look-yaw + look-pitch for remotes, and drive our own (FP-hidden) model the same way.
	aim_yaw = _camera_yaw
	aim_pitch = _camera_pitch
	if _visual:
		_visual.rotation.y = aim_yaw
		if _visual.has_method("feed_speed"):
			_visual.feed_speed(anim_speed)
		if _visual.has_method("feed_pitch"):
			_visual.feed_pitch(aim_pitch)

	if _dead:
		return

	# Rising-edge detection for jump.
	var jump_now := _input_sync.is_jump_pressed
	if jump_now and not _prev_jump_pressed:
		_jump_queued = true
	_prev_jump_pressed = jump_now

	# Cast: pressing commits the cast (cooldown), plays the gesture on all peers, and fires INSTANT
	# first-person feedback (flash + a straight tracer through the crosshair) so the shooter feels zero
	# delay. The networked bolt others see + the damage fire later, at the gesture's RELEASE frame (see
	# _on_cast_released), so it leaves the staff at the natural moment.
	if _wand and Input.is_action_pressed("cast") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _wand.begin_cast():
			play_cast_anim.rpc()
			var aim := -_camera.global_transform.basis.z
			var cam_pos := _camera.global_position
			var fp_origin := cam_pos + aim * 0.5
			_wand.fire_fp_cast(fp_origin, aim, fp_origin.distance_to(_aim_point(aim, cam_pos)))


# Crosshair target point: the camera raycast hit (excluding our own body), or a far fallback.
func _aim_point(aim: Vector3, cam_pos: Vector3) -> Vector3:
	var pt := cam_pos + aim * cast_aim_distance
	var query := PhysicsRayQueryParameters3D.create(cam_pos, pt, _AIM_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else pt


# The cast gesture reached its release frame (fired by the Visual's oneshot_released). Spawn the
# NETWORKED bolt now — from the staff at the release pose, aimed where the player is looking at this
# instant. (FP cosmetics already fired on input.) Connected only on the owner, but guard anyway since
# the gesture (and signal) play on every peer.
func _on_cast_released() -> void:
	if not is_multiplayer_authority() or _wand == null or _dead:
		return
	var aim := -_camera.global_transform.basis.z
	var cam_pos := _camera.global_position
	var aim_point := _aim_point(aim, cam_pos)
	# Origin = the staff bone on the visual (tracks the hand at the release pose). Fallback: camera-forward.
	var origin := cam_pos + aim * 0.6
	if _visual and _visual.has_method("staff_muzzle_position"):
		var sp: Vector3 = _visual.staff_muzzle_position()
		if sp.is_finite():
			origin = sp
	_wand.fire_cast(origin, (aim_point - origin).normalized())


# Owning-peer movement on the physics clock. CharacterBody3D velocity model: gravity + jump on Y,
# accelerate/decelerate the horizontal toward the wish velocity, then move_and_slide() (which slides
# along walls — no airborne wall-stick, the reason for the switch from RigidBody3D).
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _dead:
		velocity = Vector3.ZERO  # stay put while down (anim_speed is zeroed in set_dead)
		return

	# Asymmetric gravity: snappier rise, weightier fall. get_gravity().y is negative.
	if not is_on_floor():
		var mult := jump_gravity_multiplier if velocity.y > 0.0 else fall_gravity_multiplier
		velocity.y += get_gravity().y * mult * delta

	# Clear only on fire, so a jump pressed just before landing still buffers (matches prior feel).
	if _jump_queued and is_on_floor():
		velocity.y = jump_velocity
		_jump_queued = false

	# Horizontal: ease velocity toward the wish (input × camera yaw), or toward zero when idle.
	var input_dir := _input_sync.movement_vector
	var forward := Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
	var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var wish := (forward * (-input_dir.y) + right * input_dir.x).limit_length(1.0)
	if wish != Vector3.ZERO:
		var target := wish * max_speed
		velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)

	move_and_slide()

	# Author planar speed from the RESOLVED velocity (post-slide), replicated so remote copies blend
	# from a steady value. After the slide so a wall-pinned player reads ~0, not a phantom run.
	anim_speed = Vector2(velocity.x, velocity.z).length()


## Toggled by Main on death / respawn. Hides the body + gates movement/input.
func set_dead(dead: bool) -> void:
	_dead = dead
	if dead:
		# _physics_process zeroes velocity + skips move_and_slide while dead; reset the replicated
		# locomotion driver too so a stale (possibly running) blend doesn't flash on respawn.
		anim_speed = 0.0
		velocity = Vector3.ZERO
		_visual.visible = false
		_name_label.visible = false
	else:
		# Remote players show their body + name; the local first-person player keeps both hidden.
		_visual.visible = not is_multiplayer_authority()
		_name_label.visible = not is_multiplayer_authority()


func is_dead() -> bool:
	return _dead


# Dev-only: advance to the next (Form, Element) combo and re-equip via the wand's host-broadcast
# equip-sync, so every peer sees the change (the same seam pickups will use in item 6).
func _cycle_debug_spell() -> void:
	if _wand == null:
		return
	var ec := SpellCatalog.element_count()
	var total := SpellCatalog.form_count() * ec
	if total <= 0:
		return
	var linear := (_wand.form_idx * ec + _wand.element_idx + 1) % total
	# Intended integer division: linear / ec is the form index, linear % ec the element index.
	@warning_ignore("integer_division")
	_wand.request_set_blend(linear / ec, linear % ec)


# ── RPC: owner → all cast-animation broadcast ──
# Fired by the owning peer when a cast actually happens. The player node's authority IS the owning
# peer, so an "authority, call_local" RPC broadcasts to all peers (incl. the owner) — the same shape
# the host uses for the enemy attack. The local FP player's Visual is hidden, so the owner doesn't see
# its own gesture (expected in first-person); remotes do. Cosmetic only — never touches game state.
@rpc("authority", "call_local", "reliable")
func play_cast_anim() -> void:
	if _visual and _visual.has_method("fire_oneshot"):
		_visual.fire_oneshot()


# Debug-only authority probe. Gated on the DEBUG autoload existing (it's disabled by default, no
# `*`, so this is silent in normal play and exported builds — it only fires during a two-window
# `debug_autostart` session). Prints, from THIS peer's view, what authority each player copy got.
func _log_authority_if_debug() -> void:
	if get_node_or_null("/root/DEBUG") == null:
		return
	print("[AUTH] peer %d sees Player '%s': authority=%d is_mine=%s" % [
		multiplayer.get_unique_id(), name, get_multiplayer_authority(), is_multiplayer_authority()])
