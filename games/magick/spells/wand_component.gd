class_name WandComponent
extends Node

## Holds the equipped spell and casts it. Lives on the player (added in code by player.gd so every
## peer's copy has it at the same node path, which RPC routing needs).
##
## Casting is initiated on the authority (owning) peer: it fires instant LOCAL cosmetic feedback so
## the cast feels immediate, then the actual effect is spawned + resolved on the HOST (host-
## authoritative). On clients that means an RPC to the host; on the host it runs directly. The local
## flash is cosmetic only, never touches game state.
##
## The equipped spell is built from SpellCatalog by index (form_idx / element_idx). Those indices are
## set from the replicated player spawn config, so every peer builds the SAME spell — required,
## because the host resolves a client's cast using ITS copy of that client's wand. Changing the
## equipped spell at runtime (debug cycle now, pickups later) goes through the host-broadcast
## equip-sync RPC below so all peers stay identical.

@export var equipped_spell: Spell
@export var cast_delay_sec: float = 0.35
# Host-gate slack (sec). The owner legitimately takes its cooldown at INPUT, but the host sees a
# client's casts at RELEASE + latency, so arrival spacing jitters around cast_delay_sec. The host
# rejects a request only while its copy's cooldown still has MORE than this left — enough slack to
# absorb network jitter without dropping honest casts, while still capping a modified/spamming
# client near the real cast rate.
@export var host_cast_gate_tolerance_sec: float = 0.1
# Max distance (m) a client-supplied cast origin may sit from its player's body before the host
# pulls it back. Generous: staff offset (~1 m) + replication lag at full sprint fit well inside
# it; only a forged "cast from across the map" origin trips it.
@export var max_cast_origin_offset_m: float = 4.0

# Preloaded (not class_name) so the isolated --check-only gate doesn't false-error on the sibling type.
const _SPELL_TRACER := preload("res://games/magick/projectiles/spell_tracer.gd")

# Catalog indices for the equipped blend; set by player.gd before this node enters the tree.
var form_idx: int = 0
var element_idx: int = 0

var _cooldown: float = 0.0


func _ready() -> void:
	if equipped_spell == null:
		equipped_spell = SpellCatalog.make_blend(form_idx, element_idx)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


func can_cast() -> bool:
	return _cooldown <= 0.0 and equipped_spell != null


## Commit a cast on the authority peer: gate on cooldown, take the cooldown, and return whether it
## committed (so the caller plays the gesture only on real casts). The actual effect is deferred to
## fire_cast(), called at the gesture's release frame — the cooldown is taken HERE (at input) so the
## button can't be spammed during the wind-up.
func begin_cast() -> bool:
	if not can_cast():
		return false
	_cooldown = cast_delay_sec
	return true


## The host-authoritative networked bolt (what OTHER players see + the damage), fired at the gesture's
## RELEASE frame from the staff. Direct on the host, RPC from a client. No cooldown logic and no local
## cosmetics here — begin_cast() gated it, and the caster's instant feedback fires on input (fire_fp_cast).
func fire_cast(origin: Vector3, direction: Vector3) -> void:
	if equipped_spell == null:
		return
	if multiplayer.is_server():
		equipped_spell.cast_on_host(get_tree().current_scene, origin, direction, multiplayer.get_unique_id())
	else:
		_request_cast.rpc_id(1, origin, direction)


## INSTANT first-person feedback, fired on input (caster's screen only): the muzzle flash + the local
## straight SpellTracer through the crosshair. Decoupled from the networked bolt (fire_cast, at release)
## so the shooter feels zero delay while others still see the bolt leave the staff at the gesture peak.
func fire_fp_cast(origin: Vector3, direction: Vector3, max_dist: float) -> void:
	if equipped_spell == null:
		return
	_spawn_local_muzzle_flash(origin, equipped_spell.muzzle_color())
	var tracer := _SPELL_TRACER.new()
	get_tree().current_scene.add_child(tracer)
	tracer.setup(origin, direction, equipped_spell.projectile_speed(), equipped_spell.muzzle_color(),
		equipped_spell.projectile_lifetime(), max_dist)


func current_spell_text() -> String:
	return equipped_spell.describe() if equipped_spell else "(none)"


## Cosmetic cast SFX for the equipped spell (its Element's stream). player.gd plays it on every peer
## via the cast RPC; asking the wand keeps player.gd from reaching into equipped_spell directly.
func cast_sound() -> AudioStream:
	return equipped_spell.cast_sound() if equipped_spell else null


## Re-equip to a catalog (form, element). Called by the owning peer; resolves host-authoritatively
## and broadcasts so every peer rebuilds this wand identically. The seam pickups (item 6) reuse.
func request_set_blend(new_form_idx: int, new_element_idx: int) -> void:
	if multiplayer.is_server():
		_host_apply_set_blend(new_form_idx, new_element_idx)
	else:
		_request_set_blend.rpc_id(1, new_form_idx, new_element_idx)


# ── Local cosmetic feedback (caster's screen only — never affects game state) ──
func _spawn_local_muzzle_flash(origin: Vector3, color: Color) -> void:
	var flash := OmniLight3D.new()
	flash.omni_range = 4.0
	flash.light_color = color
	flash.light_energy = 4.0
	get_tree().current_scene.add_child(flash)
	flash.global_position = origin
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.12)
	tween.tween_callback(flash.queue_free)


func _host_apply_set_blend(new_form_idx: int, new_element_idx: int) -> void:
	# Clamp to the catalog so a bad index can't desync peers.
	var f := clampi(new_form_idx, 0, SpellCatalog.form_count() - 1)
	var e := clampi(new_element_idx, 0, SpellCatalog.element_count() - 1)
	_set_blend.rpc(f, e)


# ── RPC: client → host cast request ──
# The client's begin_cast() gate is FEEL, not authority — the host enforces the cast rate here on
# its own copy of this wand (its _cooldown already ticks on every peer; only this RPC sets it on
# the host copy, since begin_cast runs owner-only). Origin/direction are client-supplied intent:
# direction is re-normalized, origin is clamped near the caster's authoritative body position.
@rpc("any_peer", "call_remote", "reliable")
func _request_cast(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var caster_peer := multiplayer.get_remote_sender_id()
	if equipped_spell == null:
		return
	if direction.length_squared() < 0.0001:
		return  # degenerate aim — a zero direction would spawn a bolt that never moves
	if _cooldown > host_cast_gate_tolerance_sec:
		return  # faster than cast_delay_sec allows (beyond jitter slack) — drop the request
	_cooldown = cast_delay_sec
	equipped_spell.cast_on_host(
		get_tree().current_scene, _clamp_origin_to_body(origin), direction.normalized(), caster_peer)


# Pull a client-supplied cast origin back toward the caster's body if it's implausibly far
# (forged, or badly stale). The wand's parent IS the player node; on the host that body position
# is the authoritative one. Falls through unchanged when the parent isn't a Node3D (defensive —
# the wand is always added to the player in player.gd).
func _clamp_origin_to_body(origin: Vector3) -> Vector3:
	var body := get_parent() as Node3D
	if body == null:
		return origin
	var from_body := origin - body.global_position
	if from_body.length_squared() <= max_cast_origin_offset_m * max_cast_origin_offset_m:
		return origin
	return body.global_position + from_body.limit_length(max_cast_origin_offset_m)


# ── RPC: client → host equip-change request ──
@rpc("any_peer", "call_remote", "reliable")
func _request_set_blend(new_form_idx: int, new_element_idx: int) -> void:
	if not multiplayer.is_server():
		return
	# Sender is the owning peer of this wand's player; trusted (friends-only co-op).
	_host_apply_set_blend(new_form_idx, new_element_idx)


# ── RPC: host → all equip broadcast ──
# any_peer (not authority) because this wand lives on a CLIENT-owned player node when it isn't the
# host's own — an "authority" RPC from the host would be rejected there. Host-originated only
# (request_set_blend / _request_set_blend both guard on is_server before reaching here).
@rpc("any_peer", "call_local", "reliable")
func _set_blend(new_form_idx: int, new_element_idx: int) -> void:
	form_idx = new_form_idx
	element_idx = new_element_idx
	equipped_spell = SpellCatalog.make_blend(new_form_idx, new_element_idx)
