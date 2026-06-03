class_name BlendSpell
extends Spell

## One Form + one Element, fused into a single cast. The locked blend engine.

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
		"damage": element.damage,
		"color": element.color,
		"owner": caster_peer,
	})


func muzzle_color() -> Color:
	return element.color if element else Color.WHITE


func describe() -> String:
	var e := element.display_name if element else "?"
	var f := form.display_name if form else "?"
	return "%s %s" % [e, f]
