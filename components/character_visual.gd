class_name CharacterVisual
extends Node3D

## Holds an entity's visible body and swaps in a real model at runtime IF the asset is present,
## otherwise keeps the committed placeholder mesh that lives under this node in the scene.
##
## WHY RUNTIME-OPTIONAL: the model files (paid KayKit packs) are gitignored — the repo is public and
## can't redistribute them — so the committed code must not hard-depend on them. A clean checkout (and
## the headless gate) keeps the placeholder; a machine that has assets/ gets the real model. The model
## is loaded by STRING PATH at runtime (never a scene ext_resource), so no committed scene references a
## gitignored file. Visuals are cosmetic only — this never touches authority / collision / replication.

## Path to a model scene (e.g. a KayKit .glb). Empty or missing -> keep the placeholder.
@export_file("*.glb", "*.gltf", "*.tscn", "*.scn") var model_path: String = ""
## Alignment for the swapped-in model (tune in the editor — feet at the capsule bottom, facing, size).
## The capsule collider is height 1.8 centred on the node origin, so feet sit ~0.9 below origin.
@export var model_offset: Vector3 = Vector3(0.0, -0.9, 0.0)
@export var model_scale: float = 1.0
@export var model_yaw_deg: float = 0.0


func _ready() -> void:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return  # asset absent — keep the committed placeholder child(ren)
	var packed := load(model_path) as PackedScene
	if packed == null:
		return
	var placeholders := get_children()  # the authored placeholder mesh(es)
	var model := packed.instantiate()
	add_child(model)
	model.position = model_offset
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = deg_to_rad(model_yaw_deg)
	for p in placeholders:
		p.queue_free()
