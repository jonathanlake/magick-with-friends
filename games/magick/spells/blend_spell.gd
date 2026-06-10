class_name BlendSpell
extends Spell

## One Form + one Element, fused into a single cast. The locked blend engine. Flattens both into a
## flat config of primitives (no Resource crosses the wire) for the projectile spawner; the host
## resolves the hit + reaction from those values.

@export var form: SpellForm
@export var element: SpellElement


func cast_on_host(arena: Node, origin: Vector3, direction: Vector3, caster_peer: int) -> void:
	if form == null or element == null:
		return
	if not arena.has_method("spawn_projectile"):
		return
	arena.spawn_projectile({
		"pos": origin,
		"dir": direction,
		"speed": form.projectile_speed,
		"lifetime": form.projectile_lifetime_sec,
		"aoe_radius": form.aoe_radius,
		"explode": form.explode_on_impact,
		"damage": element.damage,
		"color": element.color,
		"reaction": int(element.reaction),
		"chain_count": element.chain_count,
		"chain_range": element.chain_range,
		"chain_falloff": element.chain_falloff,
		"burn_dps": element.burn_dps,
		"burn_duration": element.burn_duration_sec,
		"owner": caster_peer,
	})


func muzzle_color() -> Color:
	return element.color if element else Color.WHITE


func cast_sound() -> AudioStream:
	return element.cast_sound if element else null


func projectile_speed() -> float:
	return form.projectile_speed if form else 28.0


func projectile_lifetime() -> float:
	return form.projectile_lifetime_sec if form else 3.0


func describe() -> String:
	if display_name != "Spell" and display_name != "":
		return display_name
	var e := element.display_name if element else "?"
	var f := form.display_name if form else "?"
	return "%s %s" % [e, f]
