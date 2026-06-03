class_name Spell
extends Resource

## A spell is the thing a wand casts. Common seam: `cast_on_host` runs on the HOST and
## produces the actual effect by asking `arena` (the Main node) to spawn projectiles.
## Subclasses implement it:
##   - BlendSpell  : fuses one Form + one Element into a single fused effect (the engine).
##   - CascadeSpell: an authored split->chain->explode example for the PR5 A/B (no engine).

@export var display_name: String = "Spell"


## Runs on the host only. `arena` exposes `spawn_projectile(config: Dictionary)`.
func cast_on_host(_arena: Node, _origin: Vector3, _direction: Vector3, _caster_peer: int) -> void:
	pass


## Cosmetic muzzle colour for the instant local cast feedback (caster's screen only).
func muzzle_color() -> Color:
	return Color.WHITE


func describe() -> String:
	return display_name
