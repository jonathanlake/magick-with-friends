class_name HitFlashComponent
extends Node

## Reusable hit-flash feedback. Drop it under any entity that has a visual mesh (and usually a
## HealthComponent) to make that mesh momentarily flash a color when the entity takes damage.
## Knows nothing about players/enemies/spells — pure presentation, so any game/level can reuse it.
##
## Wiring uses NodePath exports resolved in _ready (typed-node @exports do NOT resolve from a
## hand-authored .tscn — they come back null).
##
## Networking: damage is host-authoritative in this project, so HealthComponent.damaged fires only
## on the host. The host fans the cosmetic flash out to every peer via flash_remote(). The RPC is
## `any_peer` (not `authority`) so the host can trigger it on a CLIENT-owned node (e.g. a player,
## whose authority is its owning peer, not the host) — an `authority` RPC would be rejected there.
## The flash is cosmetic only and never touches game state.

@export var target_mesh_path: NodePath
@export var flash_color: Color = Color(1.0, 1.0, 1.0)
@export var flash_duration_sec: float = 0.3
## Optional: path to a HealthComponent whose `damaged` signal auto-triggers the flash. Leave empty
## to drive the flash manually via flash() / flash_remote.rpc() from other game logic.
@export var health_component_path: NodePath
## Skip the flash on a lethal hit. Avoids a reliable RPC + tween on an entity being freed the same
## frame (enemies queue_free on death); the killing blow shows death feedback instead.
@export var skip_on_lethal: bool = true

var _mesh: MeshInstance3D
var _health: HealthComponent
var _base_albedo: Color = Color.WHITE
var _flash_tween: Tween


func _ready() -> void:
	_mesh = get_node_or_null(target_mesh_path) as MeshInstance3D
	_health = get_node_or_null(health_component_path) as HealthComponent
	var mat := _material()
	if mat:
		_base_albedo = mat.albedo_color
	if _health:
		_health.damaged.connect(_on_damaged)


## Local cosmetic flash — swaps the mesh albedo to flash_color and tweens it back. Safe to call on
## any peer; affects only this machine's view of this entity.
func flash() -> void:
	var mat := _material()
	if mat == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	mat.albedo_color = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(mat, "albedo_color", _base_albedo, flash_duration_sec)


func _on_damaged() -> void:
	# Damage resolves on the host in this project, so damaged fires here only on the host; the host
	# fans the flash to every peer.
	if not multiplayer.is_server():
		return
	if skip_on_lethal and _health and _health.current_health <= 0:
		return
	flash_remote.rpc()


func _material() -> StandardMaterial3D:
	return _mesh.material_override as StandardMaterial3D if _mesh else null


# ── RPC: host → all peers, cosmetic flash fan-out ──
@rpc("any_peer", "call_local", "reliable")
func flash_remote() -> void:
	flash()
