class_name EnemyBase
extends CharacterBody3D

## Host-authoritative melee enemy. The host runs ALL AI (steer to the nearest alive player,
## melee on a cooldown) and resolves damage; clients only receive global_position from the
## child MultiplayerSynchronizer and run no logic. Spawned by Main's EnemySpawner via a
## spawn_function that runs on every peer with the same config (so visuals match). Damage TO
## the enemy is host-only too: the projectile calls our HealthComponent.damage() directly
## (see projectile.gd), and death queue_free()s on the host, which replicates the removal.

@export var move_speed: float = 4.0
@export var melee_damage: int = 10
@export var melee_range: float = 2.0
@export var attack_cooldown_sec: float = 1.0
@export var flash_color: Color = Color(1.0, 0.5, 0.0)  # orange hit feedback
@export var flash_duration_sec: float = 0.3

@onready var _health: HealthComponent = $HealthComponent
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _attack_timer: float = 0.0
var _arena: Node
var _base_albedo: Color = Color.WHITE
var _flash_tween: Tween


func _enter_tree() -> void:
	# Enemies are always host-simulated (peer 1). Set authority before the child
	# MultiplayerSynchronizer registers (recursive by default) — see CLAUDE.md timing rule.
	set_multiplayer_authority(1)


func _ready() -> void:
	_arena = get_tree().current_scene
	_health.died.connect(_on_died)
	# Hit-flash feedback. The material is resource_local_to_scene, so each enemy owns its copy
	# and only the hit one flashes. damage() runs host-side, so we fan the flash out over RPC.
	var mat := _mesh.material_override as StandardMaterial3D
	if mat:
		_base_albedo = mat.albedo_color
	_health.damaged.connect(_on_damaged)
	# Maintain the shared live count via the event bus (on every peer — spawn replicates here too),
	# so the HUD/console don't have to poll Main's "Enemies" node.
	GameEvents.register_enemy()


func _exit_tree() -> void:
	GameEvents.unregister_enemy()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return  # clients receive global_position only; no AI here

	velocity += get_gravity() * delta

	var target := _find_nearest_player()
	if target != null:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		if dist > 0.001:
			var dir := to_target / dist
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
		_attack_timer -= delta
		if dist <= melee_range and _attack_timer <= 0.0:
			_attack_timer = attack_cooldown_sec
			# Player damage is host-authoritative and routed through Main (RPC health sync).
			if _arena.has_method("apply_player_damage"):
				_arena.apply_player_damage(target.peer_id, melee_damage)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


# Pick the closest still-alive player. Uses the "players" group (maintained by the engine)
# instead of scanning + casting every Main child each physics frame.
func _find_nearest_player() -> Player:
	var nearest: Player = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or p.is_dead():
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest


func _on_died() -> void:
	if not is_multiplayer_authority():
		return  # host owns death; queue_free replicates the removal to clients
	GameEvents.emit_enemy_died()
	queue_free()


# Host-only: damage() runs on the host, so fan the cosmetic flash out to every peer.
func _on_damaged() -> void:
	if not is_multiplayer_authority():
		return
	# HealthComponent emits `damaged` after clamping, so health is already 0 on a lethal hit.
	# Skip the flash then: _on_died queue_free()s this enemy the same frame, and a reliable RPC
	# + tween on a node being removed just spams "node not found" on clients.
	if _health.current_health <= 0:
		return
	flash_damage.rpc()


@rpc("authority", "call_local", "reliable")
func flash_damage() -> void:
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	mat.albedo_color = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(mat, "albedo_color", _base_albedo, flash_duration_sec)
