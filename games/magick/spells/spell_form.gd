class_name SpellForm
extends Resource

## The delivery shape — where the mechanical distinctness lives. Element-agnostic: a Form is the
## same shape no matter which Element fills it. Slice set: Projectile (single bolt) + AoE Burst
## (a bolt that detonates into a radius). Beam / Cone / Wall / Bubble / Trap orb come later; ceiling ~7.

@export var display_name: String = "Projectile"
@export var projectile_speed: float = 28.0
@export var projectile_lifetime_sec: float = 3.0

## AoE Burst fields. aoe_radius == 0 means single-target (plain Projectile). When explode_on_impact
## is true the projectile detonates on first contact (or at lifetime end) and damages every unit
## within aoe_radius instead of just the body it touched.
@export var aoe_radius: float = 0.0
@export var explode_on_impact: bool = false
