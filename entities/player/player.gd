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
# Spell origin marker on the staff (under the Camera3D so it tracks the full look direction). Casts
# spawn the projectile + muzzle flash from here instead of the camera/face. Read on the OWNING peer
# (where the camera is live), so a Camera3D-child marker is correct even though remotes don't run the
# camera. Falls back to a camera-forward offset if the marker is missing.
@onready var _muzzle: Marker3D = get_node_or_null("CameraRig/Camera3D/Muzzle")

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
		# and feed it the replicated speed (steady value -> no remote blend jitter).
		if _visual:
			_visual.rotation.y = aim_yaw
			if _visual.has_method("feed_speed"):
				_visual.feed_speed(anim_speed)
		return

	var target := global_position + Vector3(0.0, camera_height, 0.0)
	_camera_rig.global_position = _camera_rig.global_position.lerp(target, camera_smoothing * delta)
	_camera_rig.global_rotation.y = _camera_yaw
	_camera.rotation.x = _camera_pitch

	# Publish our look-yaw for remotes, and face our own (FP-hidden) model the same way.
	aim_yaw = _camera_yaw
	if _visual:
		_visual.rotation.y = aim_yaw
		if _visual.has_method("feed_speed"):
			_visual.feed_speed(anim_speed)

	if _dead:
		return

	# Rising-edge detection for jump.
	var jump_now := _input_sync.is_jump_pressed
	if jump_now and not _prev_jump_pressed:
		_jump_queued = true
	_prev_jump_pressed = jump_now

	# Cast: read locally on the authority peer; the wand gates by its own cooldown. Spawn from the
	# staff muzzle (not the face); aim stays camera-forward. Fan the cast gesture to all peers only
	# when a cast actually fired (try_cast returns true), so remotes see the swing on real casts.
	if _wand and Input.is_action_pressed("cast") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var aim := -_camera.global_transform.basis.z
		var origin := _muzzle.global_position if _muzzle else _camera.global_position + aim * 0.6
		if _wand.try_cast(origin, aim):
			play_cast_anim.rpc()


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
