class_name Projectile
extends Area3D

## Host-authoritative spell projectile. Spawned by Main's ProjectileSpawner via a custom
## spawn_function that runs on every peer with the same config (so visuals match). Only the host
## moves it and resolves hits — including friendly fire. Position replicates host -> clients via the
## child MultiplayerSynchronizer. Main is at the world origin, so local `position` == `global_position`.
##
## Two Forms ride this one entity: a single-target Projectile (aoe_radius 0) and an AoE Burst
## (explode_on_impact, aoe_radius > 0) that detonates into a radius. The element's reaction params
## travel in the config as primitives; the host hands them to Main.resolve_spell_hit / _burst, which
## forward to the Reactions node (damage + chain/burn + cosmetics).

var _velocity: Vector3 = Vector3.ZERO
var _owner_peer: int = 0
var _life_sec: float = 3.0
var _color: Color = Color.WHITE
var _aoe_radius: float = 0.0
var _explode: bool = false
# Element reaction payload, forwarded verbatim to the Reactions resolver on hit.
var _params: Dictionary = {}
var _resolved: bool = false


## Called by the spawn_function on every peer, before _ready, with the replicated config.
func setup(config: Dictionary) -> void:
	position = config["pos"]
	_velocity = (config["dir"] as Vector3).normalized() * float(config["speed"])
	_life_sec = float(config["lifetime"])
	_owner_peer = int(config["owner"])
	_color = config["color"]
	_aoe_radius = float(config.get("aoe_radius", 0.0))
	_explode = bool(config.get("explode", false))
	_params = {
		"damage": int(config["damage"]),
		"color": _color,
		"reaction": int(config.get("reaction", 0)),
		"chain_count": int(config.get("chain_count", 0)),
		"chain_range": float(config.get("chain_range", 6.0)),
		"chain_falloff": float(config.get("chain_falloff", 0.6)),
		"burn_dps": int(config.get("burn_dps", 0)),
		"burn_duration": float(config.get("burn_duration", 0.0)),
	}
	# Bursts also collide with the world (mask bit 1) so they detonate on walls/floor; single-target
	# bolts keep the default mask 6 (players + enemies, pass through world).
	if _explode:
		collision_mask = 7


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _color
		mat.emission_enabled = true
		mat.emission = _color
		mesh.material_override = mat
		if _explode:
			mesh.scale = Vector3.ONE * 1.8   # bursts read as a bigger, heavier orb
		# First-person dual-visual: hide the networked bolt for the CASTER — they see a straight local
		# tracer from the camera instead (SpellTracer), while everyone else sees this bolt leave the
		# staff. Collision/damage are unaffected (Area3D monitoring is independent of mesh visibility),
		# so the host still resolves the hit from this networked projectile.
		if _owner_peer == multiplayer.get_unique_id():
			mesh.visible = false


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return  # host owns movement + lifetime
	position += _velocity * delta
	_life_sec -= delta
	if _life_sec <= 0.0:
		if _explode and not _resolved:
			_detonate()
		else:
			queue_free()


func _on_body_entered(body: Node) -> void:
	if not is_multiplayer_authority() or _resolved:
		return
	# Don't let the caster's own body trigger at the muzzle (they can still be caught in a burst).
	if body is Player and body.peer_id == _owner_peer:
		return
	var arena := get_tree().current_scene
	if _explode:
		_detonate()
		return
	# Single-target: resolve on the first player/enemy contact.
	if body is Player or body.has_node("HealthComponent"):
		_resolved = true
		if arena.has_method("resolve_spell_hit"):
			arena.resolve_spell_hit(body, _params, _owner_peer)
		queue_free()


func _detonate() -> void:
	_resolved = true
	var arena := get_tree().current_scene
	if arena.has_method("resolve_spell_burst"):
		arena.resolve_spell_burst(global_position, _aoe_radius, _params, _owner_peer)
	queue_free()
