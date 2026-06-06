class_name LocomotionAnimator
extends Node3D

## Drives a locomotion BlendSpace1D (idle <-> run) from how fast the entity is actually moving.
## Attach to a visual scene root (the Node3D that holds the model + AnimationTree); it reads the
## node's own world-space motion, so it Just Works on the player and (next pass) the enemy.
##
## Multiplayer: the idiomatic Godot approach is NOT to replicate animation state — replicate the
## minimal driver and derive the animation locally on every peer. We already sync global_position
## (mode 1), and this node moves with the body, so every peer measures the same speed from its own
## position delta and feeds the same BlendSpace1D. No new replicated fields, no RPCs — purely local
## presentation, identical on all machines.
##
## Sampling runs in _physics_process, NOT _process: the body moves on the physics clock (the local
## player in _integrate_forces, remote players via their MultiplayerSynchronizer on the physics
## step), so reading position there gives a clean, fixed-step speed. Sampling in _process (render
## rate) instead reads stair-stepped positions — some frames zero motion, the next a doubled jump —
## which makes the derived speed flicker, jittering the blend (most visible at the staff tip).
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
## BlendSpace1D blend parameter on the AnimationTree.
@export var blend_param: String = "parameters/blend_position"

var _tree: AnimationTree
var _last_pos: Vector3
var _blend: float = 0.0
var _has_last_pos: bool = false


func _ready() -> void:
	_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if _tree == null:
		push_warning("LocomotionAnimator: no AnimationTree at %s" % [animation_tree_path])
		set_physics_process(false)
		return
	_tree.active = true
	_last_pos = global_position
	_has_last_pos = true


func _physics_process(delta: float) -> void:
	if _tree == null or delta <= 0.0:
		return

	# Horizontal speed from this node's own world motion — measured identically on every peer.
	var here := global_position
	if not _has_last_pos:
		_last_pos = here
		_has_last_pos = true
		return
	var planar := here - _last_pos
	planar.y = 0.0
	_last_pos = here
	var speed := planar.length() / delta

	# Normalize to 0..1 and ease toward it so the blend doesn't jitter with frame-to-frame noise.
	var target := clampf(speed / maxf(run_speed, 0.001), 0.0, 1.0)
	_blend = lerpf(_blend, target, clampf(blend_smoothing * delta, 0.0, 1.0))
	_tree.set(blend_param, _blend)
