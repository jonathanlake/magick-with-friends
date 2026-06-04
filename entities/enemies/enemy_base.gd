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

@onready var _health: HealthComponent = $HealthComponent

var _attack_timer: float = 0.0
var _arena: Node


func _enter_tree() -> void:
	# Enemies are always host-simulated (peer 1). Set authority before the child
	# MultiplayerSynchronizer registers (recursive by default) — see CLAUDE.md timing rule.
	set_multiplayer_authority(1)


func _ready() -> void:
	_arena = get_tree().current_scene
	_health.died.connect(_on_died)


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
				_arena.apply_player_damage(int(str(target.name)), melee_damage)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


# Players are direct children of Main, named str(peer_id). Pick the closest one still alive.
func _find_nearest_player() -> Player:
	var nearest: Player = null
	var nearest_dist := INF
	for child in _arena.get_children():
		var p := child as Player
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
