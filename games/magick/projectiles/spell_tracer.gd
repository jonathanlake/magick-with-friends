class_name SpellTracer
extends MeshInstance3D

## Local FIRST-PERSON cosmetic only (the casting peer's screen). It flies dead-straight from just
## ahead of the camera through the crosshair, so the caster's own shot reads as going straight to where
## they're aiming. Meanwhile the real, networked projectile — spawned from the staff muzzle and HIDDEN
## for the caster (see projectile.gd) — is what OTHER players see leave the staff. This tracer is never
## networked and has no collision; the host's hidden projectile does all the damage. It frees itself at
## the crosshair-hit distance (max_dist) or after the spell's lifetime, whichever comes first.

var _velocity: Vector3 = Vector3.ZERO
var _life_sec: float = 3.0
var _max_dist: float = 1e9
var _traveled: float = 0.0


## origin/direction in world space; speed + lifetime + color match the real projectile; max_dist is
## the distance to the crosshair target so the bolt stops where the player aimed.
func setup(origin: Vector3, direction: Vector3, speed: float, color: Color, lifetime: float, max_dist: float) -> void:
	global_position = origin
	_velocity = direction.normalized() * speed
	_life_sec = lifetime
	_max_dist = max_dist
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	material_override = mat


func _process(delta: float) -> void:
	var step := _velocity * delta
	global_position += step
	_traveled += step.length()
	_life_sec -= delta
	if _life_sec <= 0.0 or _traveled >= _max_dist:
		queue_free()
