class_name WandComponent
extends Node

## Holds the equipped spell and casts it. Lives on the player (added in code by player.gd
## so every peer's copy has it at the same node path, which RPC routing needs).
##
## Casting is initiated on the authority (owning) peer: it fires instant LOCAL cosmetic
## feedback so the cast feels immediate, then the actual effect is spawned + resolved on
## the HOST (host-authoritative). On clients that means an RPC to the host; on the host it
## runs directly. The local flash is the netcode-feel fix from the plan — cosmetic only,
## never touches game state.

@export var equipped_spell: Spell
@export var cast_delay_sec: float = 0.35

var _cooldown: float = 0.0


func _ready() -> void:
	# Slice default, built in code (no .tres yet): a Fire Projectile blend spell.
	# Built identically on every peer, so the host's copy of a client's wand can resolve
	# the cast. (PR6 will sync equipped form/element when pickups can change them.)
	if equipped_spell == null:
		var blend := BlendSpell.new()
		blend.form = SpellForm.new()
		blend.element = SpellElement.new()
		blend.display_name = "Fire Projectile"
		equipped_spell = blend


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


# ── RPC: client → host cast request ──
@rpc("any_peer", "call_remote", "reliable")
func _request_cast(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var caster_peer := multiplayer.get_remote_sender_id()
	if equipped_spell:
		equipped_spell.cast_on_host(get_tree().current_scene, origin, direction, caster_peer)
