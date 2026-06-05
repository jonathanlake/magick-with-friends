extends Node

## The list of Forms and Elements that exist in the game, built in code (no .tres yet). This is the
## single source of truth for "what can be cast", and the future loot table for pickups (item 6).
##
## INDEX-STABLE CONTRACT: spell picks travel the wire as ints (form_idx / element_idx in the player
## spawn config + the equip-sync RPC), so the order of these arrays IS the protocol. Append new
## entries, never reorder or remove — an index must mean the same thing on every peer.

var forms: Array[SpellForm] = []
var elements: Array[SpellElement] = []

# Themed [Element][Form] names, keyed "form_idx,element_idx". Falls back to "<Element> <Form>".
const _NAMES := {
	"0,0": "Firebolt",     # Projectile + Fire
	"1,0": "Fireball",     # Burst + Fire
	"0,1": "Spark",        # Projectile + Lightning
	"1,1": "Thunderclap",  # Burst + Lightning
}


func _ready() -> void:
	forms = [_projectile(), _burst()]
	elements = [_fire(), _lightning()]


func form_count() -> int:
	return forms.size()


func element_count() -> int:
	return elements.size()


func form(idx: int) -> SpellForm:
	return forms[clampi(idx, 0, forms.size() - 1)]


func element(idx: int) -> SpellElement:
	return elements[clampi(idx, 0, elements.size() - 1)]


## Build a BlendSpell from catalog indices. Called identically on every peer (the indices come from
## the replicated spawn config / equip-sync RPC), so each peer's copy of a wand is the same spell.
func make_blend(form_idx: int, element_idx: int) -> BlendSpell:
	var blend := BlendSpell.new()
	blend.form = form(form_idx)
	blend.element = element(element_idx)
	blend.display_name = blend_name(form_idx, element_idx)
	return blend


func blend_name(form_idx: int, element_idx: int) -> String:
	var key := "%d,%d" % [form_idx, element_idx]
	if _NAMES.has(key):
		return _NAMES[key]
	return "%s %s" % [element(element_idx).display_name, form(form_idx).display_name]


# ── Catalog content ──

func _projectile() -> SpellForm:
	var f := SpellForm.new()
	f.display_name = "Projectile"
	f.projectile_speed = 28.0
	f.projectile_lifetime_sec = 3.0
	f.aoe_radius = 0.0
	f.explode_on_impact = false
	return f


func _burst() -> SpellForm:
	var f := SpellForm.new()
	f.display_name = "Burst"
	f.projectile_speed = 18.0          # slower + heavier than a bolt, reads as a lobbed blast
	f.projectile_lifetime_sec = 3.0
	f.aoe_radius = 3.0
	f.explode_on_impact = true
	return f


func _fire() -> SpellElement:
	var e := SpellElement.new()
	e.display_name = "Fire"
	e.damage = 22
	e.color = Color(1.0, 0.45, 0.1)
	e.reaction = SpellElement.Reaction.FIRE
	e.burn_dps = 6
	e.burn_duration_sec = 3.0
	return e


func _lightning() -> SpellElement:
	var e := SpellElement.new()
	e.display_name = "Lightning"
	e.damage = 20
	e.color = Color(0.45, 0.7, 1.0)
	e.reaction = SpellElement.Reaction.LIGHTNING
	e.chain_count = 2
	e.chain_range = 6.0
	e.chain_falloff = 0.6
	return e
