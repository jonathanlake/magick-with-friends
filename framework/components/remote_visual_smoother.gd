class_name RemoteVisualSmoother
extends RefCounted

## Smooths a REMOTE (non-authority) entity's decoupled visible model. The body's global_position
## arrives in held, snapped network packets (MultiplayerSynchronizer mode 1, no interpolation), so a
## remote copy would teleport between packets. This eases a top_level Visual toward the networked
## body position + facing each frame, snaps on large jumps, and PARKS at an explicit respawn target
## until the body's replicated position catches up (so a respawn doesn't briefly show the model at
## the old death spot, nor get yanked back there while the new position is still in flight ~1 RTT).
##
## Parent-driven by design: the owner peer feeds the target in each frame (the helper never reaches
## up to read its parent). Reusable by players and (later) enemies — only the target/yaw source
## differs. The Visual is top_level here, so it ignores any body rotation; that's fine — the body is
## never rotated and we author rotation.y from the replicated look/face yaw.

const MIN_RATE := 0.001

var _visual: LocomotionAnimator
var _rate: float = MIN_RATE
var _snap_dist_sq: float = 0.0
var _parked: bool = false
var _park_pos: Vector3 = Vector3.ZERO
var _park_timeout: float = 1.0
var _park_elapsed: float = 0.0


## Configure once (on the owning entity's remote copy). rate clamped so 0/negative can't freeze or
## diverge the lerp; snap distance kept squared for a cheap per-frame compare.
func setup(visual: LocomotionAnimator, rate_per_sec: float, snap_distance_m: float, park_timeout_sec: float) -> void:
	_visual = visual
	_rate = maxf(rate_per_sec, MIN_RATE)
	_snap_dist_sq = snap_distance_m * snap_distance_m
	_park_timeout = park_timeout_sec


## Hard-place the Visual on spawn (position AND facing, so it doesn't spin-in from yaw 0).
func seed(pos: Vector3, yaw: float) -> void:
	if _visual == null:
		return
	_visual.global_position = pos
	_visual.rotation.y = yaw
	_parked = false


## Respawn: snap the Visual to the (known) spawn target and hold there until the body's replicated
## position arrives near it — bridges the ~1 RTT before the teleport syncs to this peer.
func teleport(pos: Vector3, yaw: float) -> void:
	if _visual == null:
		return
	_visual.global_position = pos
	_visual.rotation.y = yaw
	_park_pos = pos
	_parked = true
	_park_elapsed = 0.0


## Per-frame drive. Pass the body's networked position + facing + the replicated anim drivers.
func smooth(target_pos: Vector3, target_yaw: float, speed: float, pitch: float, delta: float) -> void:
	if _visual == null:
		return
	var w := 1.0 - exp(-_rate * delta)
	if _parked:
		_park_elapsed += delta
		# Resume once the body's true position has replicated near the parked target, or on timeout
		# (dropped-packet safety). Until then, hold position so the smoother can't drag the model back
		# toward the stale pre-respawn position.
		if target_pos.distance_squared_to(_park_pos) <= _snap_dist_sq or _park_elapsed >= _park_timeout:
			_parked = false
		else:
			_visual.global_position = _park_pos
			_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, w)
			_visual.feed_speed(speed)
			_visual.feed_pitch(pitch)
			return
	if _visual.global_position.distance_squared_to(target_pos) > _snap_dist_sq:
		# Large jump (teleport / heavy lag catch-up): snap position and facing rather than slide.
		_visual.global_position = target_pos
		_visual.rotation.y = target_yaw
	else:
		_visual.global_position = _visual.global_position.lerp(target_pos, w)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, w)
	_visual.feed_speed(speed)
	_visual.feed_pitch(pitch)
