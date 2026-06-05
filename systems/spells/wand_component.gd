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


## Called on the authority peer (the caster) with a world-space origin + direction.
func try_cast(origin: Vector3, direction: Vector3) -> void:
	if not can_cast():
		return
	_cooldown = cast_delay_sec
	_spawn_local_muzzle_flash(origin, equipped_spell.muzzle_color())
	if multiplayer.is_server():
		equipped_spell.cast_on_host(get_tree().current_scene, origin, direction, multiplayer.get_unique_id())
	else:
		_request_cast.rpc_id(1, origin, direction)


func current_spell_text() -> String:
	return equipped_spell.describe() if equipped_spell else "(none)"


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
@rpc("any_peer", "call_remote", "reliable")
func _request_cast(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var caster_peer := multiplayer.get_remote_sender_id()
	if equipped_spell:
		equipped_spell.cast_on_host(get_tree().current_scene, origin, direction, caster_peer)


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
