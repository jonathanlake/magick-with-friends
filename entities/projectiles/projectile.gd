class_name Projectile
extends Area3D

## Host-authoritative spell projectile. Spawned by Main's ProjectileSpawner via a custom
## spawn_function that runs on every peer with the same config (so visuals match). Only the
## host moves it and resolves hits — including friendly fire. Position replicates host ->
## clients via the child MultiplayerSynchronizer. Main is at the world origin, so local
## `position` == `global_position` here.

var _velocity: Vector3 = Vector3.ZERO
var _damage: int = 25
var _owner_peer: int = 0
var _life_sec: float = 3.0
var _color: Color = Color.WHITE


## Called by the spawn_function on every peer, before _ready, with the replicated config.
func setup(config: Dictionary) -> void:
	position = config["pos"]
	_velocity = (config["dir"] as Vector3).normalized() * float(config["speed"])
	_damage = int(config["damage"])
	_owner_peer = int(config["owner"])
	_life_sec = float(config["lifetime"])
	_color = config["color"]


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _color
		mat.emission_enabled = true
		mat.emission = _color
		mesh.material_override = mat


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return  # host owns movement + lifetime
	position += _velocity * delta
	_life_sec -= delta
	if _life_sec <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not is_multiplayer_authority():
		return
	# Don't blow yourself up at the muzzle.
	if body is Player and str(body.name) == str(_owner_peer):
		return
	var arena := get_tree().current_scene
	if body is Player:
		if arena.has_method("apply_player_damage"):
			arena.apply_player_damage(int(str(body.name)), _damage)  # friendly fire ON
		queue_free()
	elif body.has_node("HealthComponent"):
		(body.get_node("HealthComponent") as HealthComponent).damage(_damage)
		queue_free()
