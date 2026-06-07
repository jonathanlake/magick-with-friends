class_name LocomotionAnimator
extends Node3D

## Drives a locomotion BlendSpace1D (idle <-> run) from how fast the entity is actually moving.
## Attach to a visual scene root (the Node3D that holds the model + AnimationTree); it reads the
## node's own world-space motion, so it Just Works on the player and (next pass) the enemy.
##
## Multiplayer: the idiomatic Godot approach is NOT to replicate animation state — replicate the
## minimal DRIVER (speed) and derive the animation locally on every peer.
##
## Preferred driver is an externally-FED speed (see feed_speed): the entity's owning peer authors
## its real velocity and replicates that one value, so every peer — including remote copies — blends
## from a steady, network-snapshot-friendly number. The fallback (nothing fed) differentiates this
## node's own world position. That's fine for a locally-simulated body, but JITTERS for a remote
## copy: its position arrives in held network snapshots (no interpolation), so differentiating it
## reads "full speed" on a packet frame and "zero" between packets — sawtoothing the blend
## (most visible at a staff/weapon tip on a long lever from the hand bone). Feeding a synced speed
## avoids that: a held speed value just means "keep running," not "stop and start."
##
## Sampling runs in _physics_process, NOT _process: the body moves on the physics clock, so reading
## there gives a clean, fixed-step signal (sampling in _process reads stair-stepped positions).
##
## Wiring uses NodePath exports resolved in _ready (typed-node @exports do NOT resolve from a hand-
## authored .tscn — they come back null; see CLAUDE.md). Looping on the Idle/Run clips is set in the
## glb import dock (one-time author action), not here.

## The AnimationTree whose tree_root is a BlendSpace1D (idle at min, run at max).
@export var animation_tree_path: NodePath
## Speed (world units/sec) that maps to a full run. ~ the entity's max move speed. Below it, the
## blend scales linearly toward idle.
@export var run_speed: float = 12.0
## Per-second smoothing rate for the blend value — damps the noisy per-frame position delta so the
## idle<->run transition reads smoothly. Higher = snappier, lower = floatier.
@export var blend_smoothing: float = 10.0
## BlendSpace1D blend parameter on the AnimationTree. For a bare BlendSpace1D root (player) this is
## "parameters/blend_position"; nested in a BlendTree (enemy) it's "parameters/<NodeName>/blend_position".
@export var blend_param: String = "parameters/blend_position"
## Optional OneShot request parameter (e.g. "parameters/OneShot/request") for a one-shot layered over
## locomotion (the enemy attack). Empty = no one-shot, so fire_oneshot() is a no-op (the player).
@export var oneshot_request_param: String = ""
## Optional spine bone to pitch up/down from a fed look-angle (see feed_pitch). Empty = no pitch, so
## feed_pitch() is a no-op (the enemy leaves it empty for now). When set, _ready attaches a
## SpinePitchModifier to the model's Skeleton3D so the torso/head/staff tilt while legs stay planted.
@export var spine_pitch_bone: String = ""
## Clamp + axis-flip forwarded to the SpinePitchModifier (rig-dependent tuning).
@export var spine_max_pitch_deg: float = 45.0
@export var spine_invert_pitch: bool = false

const _SPINE_PITCH_MODIFIER := preload("res://components/spine_pitch_modifier.gd")

var _tree: AnimationTree
var _last_pos: Vector3
var _blend: float = 0.0
var _has_last_pos: bool = false
var _external_speed: float = 0.0
var _use_external: bool = false
# SpinePitchModifier instance (untyped: keep the sibling class_name out of static analysis so the
# isolated --check-only gate doesn't false-error on it; it's configured via the preload const below).
var _pitch_modifier: Node = null


func _ready() -> void:
	_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if _tree == null:
		push_warning("LocomotionAnimator: no AnimationTree at %s" % [animation_tree_path])
		set_physics_process(false)
		return
	_tree.active = true
	_last_pos = global_position
	_has_last_pos = true
	_setup_spine_pitch()


# Attach a SpinePitchModifier to the model's Skeleton3D (post-animation, so it composes on top of the
# locomotion/one-shot pose). No-op when spine_pitch_bone is unset, or if the model has no Skeleton3D.
func _setup_spine_pitch() -> void:
	if spine_pitch_bone == "":
		return
	var skel := _find_skeleton(self)
	if skel == null:
		push_warning("LocomotionAnimator: spine_pitch_bone set but no Skeleton3D found under %s" % name)
		return
	var mod := _SPINE_PITCH_MODIFIER.new()
	mod.bone_name = spine_pitch_bone
	mod.max_pitch_deg = spine_max_pitch_deg
	mod.invert_pitch = spine_invert_pitch
	skel.add_child(mod)
	_pitch_modifier = mod


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


## Feed the locomotion speed (world units/sec) from an external, network-smooth source — the
## entity's owning peer authors it from real velocity and replicates it, so every peer (including
## remote copies) blends from a steady value instead of differentiating a stepped network position.
## Once fed, the position-differentiation fallback is disabled for this instance.
func feed_speed(speed: float) -> void:
	_external_speed = speed
	_use_external = true


## Feed the look-pitch (radians) for the spine modifier — the owning peer authors it from its camera
## and replicates it, so every peer tilts the model the same. No-op when spine_pitch_bone is unset.
func feed_pitch(pitch: float) -> void:
	if _pitch_modifier != null:
		_pitch_modifier.pitch = pitch


## Fire the configured OneShot (the attack swing), crossfading it over whatever locomotion is playing
## and fading back when it ends. No-op when oneshot_request_param is unset. Cosmetic; callers invoke
## it on every peer (e.g. via a host-broadcast RPC) so the swing shows everywhere.
func fire_oneshot() -> void:
	if _tree != null and oneshot_request_param != "":
		_tree.set(oneshot_request_param, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _physics_process(delta: float) -> void:
	if _tree == null or delta <= 0.0:
		return

	# Normalize to 0..1 and ease toward it so the blend doesn't snap.
	var target := clampf(_sample_speed(delta) / maxf(run_speed, 0.001), 0.0, 1.0)
	_blend = lerpf(_blend, target, clampf(blend_smoothing * delta, 0.0, 1.0))
	_tree.set(blend_param, _blend)


# Preferred: the externally-fed (replicated) speed. Fallback: differentiate our own world position
# (fine for a locally-simulated body, jittery for a network-stepped remote copy — see class doc).
func _sample_speed(delta: float) -> float:
	if _use_external:
		return _external_speed
	var here := global_position
	if not _has_last_pos:
		_last_pos = here
		_has_last_pos = true
		return 0.0
	var planar := here - _last_pos
	planar.y = 0.0
	_last_pos = here
	return planar.length() / delta
