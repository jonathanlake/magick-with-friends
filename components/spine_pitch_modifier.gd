class_name SpinePitchModifier
extends SkeletonModifier3D

## Pitches one bone (and everything parented under it — torso, head, arms, the held staff) up/down by
## an externally-fed angle, layered AFTER the AnimationTree. A SkeletonModifier3D runs in the
## skeleton's post-animation modifier stack, so it composes on top of the current animated pose
## instead of fighting it (manually setting bone poses in _process would be overwritten each frame).
##
## The legs stay planted: on this rig they branch from `hips`, a SIBLING of the pitched `spine` bone,
## so rotating `spine` tilts only the upper body. Set `pitch` (radians) each frame from the owner —
## e.g. the player's replicated aim_pitch — and every peer applies it to the local skeleton.

## The bone to rotate (e.g. "spine"). Empty = inactive (the modifier no-ops), so this component is
## opt-in per visual (the enemy leaves it empty for now).
@export var bone_name: String = ""
## Clamp on the applied tilt so steep looks don't fold the model in half.
@export var max_pitch_deg: float = 45.0
## Flip the tilt direction if the rig's bone axes pitch the wrong way (rig-dependent; tune once).
@export var invert_pitch: bool = false

## Fed by the owner each frame (radians). Public so the visual's animator can set it (see feed_pitch).
var pitch: float = 0.0

var _idx: int = -1
var _resolved: bool = false


# Godot 4.4+ virtual (the no-arg _process_modification() is deprecated and not invoked in 4.6). Runs
# after the AnimationMixer's playback, so it composes on top of the current animated pose.
func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or bone_name == "":
		return
	if not _resolved:
		_idx = sk.find_bone(bone_name)
		_resolved = true
	if _idx < 0:
		return
	var limit := deg_to_rad(max_pitch_deg)
	var p := clampf(-pitch if invert_pitch else pitch, -limit, limit)
	# Pre-multiply: rotate the bone in its PARENT's frame about X (the model's right axis) so the
	# torso tilts forward/back, then keep the bone's animated rotation underneath.
	sk.set_bone_pose_rotation(_idx, Quaternion(Vector3.RIGHT, p) * sk.get_bone_pose_rotation(_idx))
