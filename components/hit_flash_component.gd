class_name HitFlashComponent
extends Node

## Reusable hit-flash feedback. Drop it under any entity with a visual (and usually a HealthComponent)
## to make the body momentarily flash a color when it takes damage. Knows nothing about
## players/enemies/spells — pure presentation, so any game/level can reuse it.
##
## Tints via a transient material_overlay (NOT by mutating the base material's albedo). This works on
## a plain placeholder mesh AND on a textured imported model (KayKit etc.): the overlay renders on top
## of the base material, so the texture is preserved, multi-surface meshes all flash, and there's no
## cross-instance bleed (material_overlay is per-MeshInstance3D). It re-walks the meshes on every flash,
## so it's robust to the runtime model swap in CharacterVisual (no _ready ordering dependency).
##
## Wiring uses a NodePath export resolved in _ready (typed-node @exports do NOT resolve from a hand-
## authored .tscn — they come back null). Point target_root_path at the node whose subtree holds the
## body meshes (the entity's "Visual" node).
##
## Networking: damage is host-authoritative here, so HealthComponent.damaged fires only on the host;
## the host fans the cosmetic flash to every peer via flash_remote(). The RPC is `any_peer` (not
## `authority`) so the host can trigger it on a CLIENT-owned node (e.g. a player, whose authority is
## its owning peer) — an `authority` RPC would be rejected there. Cosmetic only; never touches state.

@export var target_root_path: NodePath
@export var flash_color: Color = Color(1.0, 1.0, 1.0)
@export var flash_duration_sec: float = 0.3
## Optional: a HealthComponent whose `damaged` signal auto-triggers the flash. Leave empty to drive
## the flash manually via flash() / flash_remote.rpc() from other game logic.
@export var health_component_path: NodePath
## Skip the flash on a lethal hit — avoids a reliable RPC + tween on an entity being freed the same
## frame (enemies queue_free on death); the killing blow shows death feedback instead.
@export var skip_on_lethal: bool = true

const _FLASH_PEAK_ALPHA := 0.6

var _root: Node
var _health: HealthComponent
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween


func _ready() -> void:
	_root = get_node_or_null(target_root_path)
	_health = get_node_or_null(health_component_path) as HealthComponent
	# One unshaded, transparent overlay material per component instance (so two entities never share
	# and bleed into each other). Colored by flash_color; we animate only its alpha.
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, 0.0)
	if _health:
		_health.damaged.connect(_on_damaged)


## Local cosmetic flash — overlays flash_color on every visible body mesh and fades it out. Safe to
## call on any peer; affects only this machine's view of this entity.
func flash() -> void:
	if _root == null or _flash_mat == null:
		return
	var meshes := _collect_meshes(_root)
	if meshes.is_empty():
		return
	for m in meshes:
		m.material_overlay = _flash_mat
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_mat.albedo_color.a = _FLASH_PEAK_ALPHA
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, flash_duration_sec)
	_flash_tween.tween_callback(_clear_overlays.bind(meshes))


func _collect_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_meshes(c))
	return out


func _clear_overlays(meshes: Array) -> void:
	for m in meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay == _flash_mat:
			(m as MeshInstance3D).material_overlay = null


func _on_damaged() -> void:
	# Damage resolves on the host, so `damaged` fires here only on the host; the host fans the flash.
	if not multiplayer.is_server():
		return
	if skip_on_lethal and _health and _health.current_health <= 0:
		return
	flash_remote.rpc()


# ── RPC: host → all peers, cosmetic flash fan-out ──
@rpc("any_peer", "call_local", "reliable")
func flash_remote() -> void:
	flash()
