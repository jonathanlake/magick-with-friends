extends Node

## The reaction table + the single home for spell-hit damage routing. A child of Main, host-only
## logic. Projectiles (via Main's resolve_spell_hit / resolve_spell_burst forwarders) hand it a
## victim (or an area) + the element's flattened reaction params; this node applies the direct
## damage and the reaction.
##
## WHY HOST-CENTRAL (not a per-entity component): a player node's multiplayer authority is its
## OWNING peer, not the host, so a self-ticking burn component would tick on the wrong machine.
## Damage must stay host-authoritative — players via Main.apply_player_damage (RPC value-sync),
## enemies via their HealthComponent directly. So the burning registry + tick live here, on the host.
##
## Cosmetic reaction visuals (chain arcs, burst flash, burning glow) are fanned to every peer from
## here via "authority" RPCs — this node is server-authoritative (no authority set → defaults to peer
## 1), so a plain authority/call_local RPC reaches all peers (unlike the client-owned player nodes,
## which need the any_peer exception).

var _arena: Node
# unit(Node) -> { dps:int, remaining:float, accum:float, source:int }
var _burning: Dictionary = {}


func _ready() -> void:
	_arena = get_tree().current_scene


# ── Host entry points (called by projectiles on the host) ──

## Single-target hit: direct damage + this element's reaction on one victim.
func apply_hit(victim: Node, params: Dictionary, caster_peer: int) -> void:
	if not multiplayer.is_server() or victim == null:
		return
	_apply_direct_and_status(victim, params, caster_peer)
	if int(params.get("reaction", 0)) == SpellElement.Reaction.LIGHTNING:
		_chain(victim, params, caster_peer)


## Area hit (AoE Burst): direct damage + status to every unit in radius. For Lightning the burst
## IS the spread, so we don't also chain — but we draw center→unit arcs so it stays legible.
func apply_burst(center: Vector3, radius: float, params: Dictionary, caster_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var color: Color = params.get("color", Color.WHITE)
	show_burst.rpc(center, color, radius)
	var pts := PackedVector3Array()
	var is_lightning := int(params.get("reaction", 0)) == SpellElement.Reaction.LIGHTNING
	for unit in _units_in_radius(center, radius):
		_apply_direct_and_status(unit, params, caster_peer)
		if is_lightning:
			pts.append(center)
			pts.append(unit.global_position)
	if not pts.is_empty():
		show_chain.rpc(pts, color)


# ── Resolution ──

func _apply_direct_and_status(unit: Node, params: Dictionary, caster_peer: int) -> void:
	_deal(unit, int(params.get("damage", 0)), caster_peer)
	if int(params.get("reaction", 0)) == SpellElement.Reaction.FIRE:
		var dps := int(params.get("burn_dps", 0))
		var dur := float(params.get("burn_duration", 0.0))
		if dps > 0 and dur > 0.0:
			_ignite(unit, dps, dur, caster_peer)


# Route a damage amount to the right host-authoritative path.
func _deal(unit: Node, dmg: int, _caster_peer: int) -> void:
	if dmg <= 0 or not is_instance_valid(unit):
		return
	if unit is Player:
		if _arena.has_method("apply_player_damage"):
			_arena.apply_player_damage(unit.peer_id, dmg)
	else:
		var hc := unit.get_node_or_null("HealthComponent") as HealthComponent
		if hc:
			hc.damage(dmg)


func _chain(origin: Node, params: Dictionary, caster_peer: int) -> void:
	var hit: Array = [origin]
	var current: Node = origin
	var dmg := float(params.get("damage", 0)) * float(params.get("chain_falloff", 0.6))
	var rng := float(params.get("chain_range", 6.0))
	var color: Color = params.get("color", Color.WHITE)
	var pts := PackedVector3Array()
	for _i in int(params.get("chain_count", 0)):
		var nxt := _nearest_unit(current.global_position, hit, rng)
		if nxt == null:
			break
		pts.append(current.global_position)
		pts.append(nxt.global_position)
		_deal(nxt, int(round(dmg)), caster_peer)
		hit.append(nxt)
		current = nxt
		dmg *= float(params.get("chain_falloff", 0.6))
	if not pts.is_empty():
		show_chain.rpc(pts, color)


func _ignite(unit: Node, dps: int, duration: float, source_peer: int) -> void:
	var fresh := not _burning.has(unit)
	var accum: float = 0.0 if fresh else _burning[unit].accum
	_burning[unit] = {"dps": dps, "remaining": duration, "accum": accum, "source": source_peer}
	if fresh:
		set_unit_burning.rpc(unit.get_path(), true)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _burning.is_empty():
		return
	var expired: Array = []
	for unit in _burning:
		if not is_instance_valid(unit) or _is_dead(unit):
			expired.append(unit)
			continue
		var b: Dictionary = _burning[unit]
		b.remaining -= delta
		b.accum += b.dps * delta
		var whole := int(b.accum)
		if whole >= 1:
			b.accum -= whole
			_deal(unit, whole, b.source)
		if b.remaining <= 0.0:
			expired.append(unit)
	for unit in expired:
		_burning.erase(unit)
		if is_instance_valid(unit):
			set_unit_burning.rpc(unit.get_path(), false)


# ── Unit queries (group-based; cheap, deterministic, no physics queries) ──

func _all_units() -> Array:
	var units: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and not (p as Player).is_dead():
			units.append(p)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			units.append(e)
	return units


func _units_in_radius(center: Vector3, radius: float) -> Array:
	var out: Array = []
	for u in _all_units():
		if center.distance_to(u.global_position) <= radius:
			out.append(u)
	return out


func _nearest_unit(from: Vector3, exclude: Array, max_range: float) -> Node:
	var best: Node = null
	var best_d := max_range
	for u in _all_units():
		if u in exclude:
			continue
		var d := from.distance_to(u.global_position)
		if d <= best_d:
			best_d = d
			best = u
	return best


func _is_dead(unit: Node) -> bool:
	if unit is Player:
		return (unit as Player).is_dead()
	var hc := unit.get_node_or_null("HealthComponent") as HealthComponent
	return hc != null and hc.current_health <= 0


# ── Cosmetic broadcasts (authority RPCs — this node is server-authoritative) ──

@rpc("authority", "call_local", "reliable")
func show_chain(points: PackedVector3Array, color: Color) -> void:
	for i in range(0, points.size() - 1, 2):
		_spawn_arc(points[i], points[i + 1], color)


@rpc("authority", "call_local", "reliable")
func show_burst(center: Vector3, color: Color, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = maxf(radius * 2.0, 1.0)
	scene.add_child(light)
	light.global_position = center
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.tween_callback(light.queue_free)


@rpc("authority", "call_local", "reliable")
func set_unit_burning(unit_path: NodePath, on: bool) -> void:
	var unit := get_node_or_null(unit_path)
	if unit == null:
		return
	var flame := unit.get_node_or_null("BurnFlame")
	if on:
		if flame == null:
			var l := OmniLight3D.new()
			l.name = "BurnFlame"
			l.light_color = Color(1.0, 0.5, 0.12)
			l.light_energy = 2.5
			l.omni_range = 3.0
			unit.add_child(l)
	elif flame:
		flame.queue_free()


func _spawn_arc(a: Vector3, b: Vector3, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null or a.distance_to(b) < 0.001:
		return
	var seg := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.09, a.distance_to(b))
	seg.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seg.material_override = mat
	scene.add_child(seg)
	var mid := (a + b) * 0.5
	# Avoid a degenerate look_at up-vector when the segment is near-vertical.
	var up := Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	seg.global_position = mid
	seg.look_at(b, up)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.tween_callback(seg.queue_free)
