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
@onready var _visual: Node3D = $Visual

var _attack_timer: float = 0.0
var _arena: Node
# Replicated animation drivers, authored by the host (see enemy_base.tscn replication config) so
# clients animate + face from steady values instead of differentiating a stepped network position
# (the remote-jitter fix from the player pass). anim_speed -> locomotion blend; face_yaw -> heading.
var anim_speed: float = 0.0
var face_yaw: float = 0.0


func _enter_tree() -> void:
	# Enemies are always host-simulated (peer 1). Set authority before the child
	# MultiplayerSynchronizer registers (recursive by default) — see CLAUDE.md timing rule.
	set_multiplayer_authority(1)


func _ready() -> void:
	_arena = get_tree().current_scene
	_health.died.connect(_on_died)
	# Join the "enemies" group on every peer so the Reactions resolver can find enemies for
	# AoE/chain targeting (parity with players being in the "players" group).
	add_to_group("enemies")
	# Maintain the shared live count via the event bus (on every peer — spawn replicates here too),
	# so the HUD/console don't have to poll Main's "Enemies" node. Hit-flash feedback now lives in
	# a reusable HitFlashComponent wired up in enemy_base.tscn.
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
			# Face the player (model-forward convention matches the player's: forward = -Z at yaw 0).
			face_yaw = atan2(-dir.x, -dir.z)
			if dist > melee_range:
				velocity.x = dir.x * move_speed
				velocity.z = dir.z * move_speed
			else:
				# In range: stop and swing — a stand-and-attack reads better than running in place.
				velocity.x = 0.0
				velocity.z = 0.0
		_attack_timer -= delta
		if dist <= melee_range and _attack_timer <= 0.0:
			_attack_timer = attack_cooldown_sec
			play_attack_anim.rpc()  # cosmetic swing on every peer (host owns the enemy)
			# Player damage is host-authoritative and routed through Main (RPC health sync).
			if _arena.has_method("apply_player_damage"):
				_arena.apply_player_damage(target.peer_id, melee_damage)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# Author the locomotion speed from real horizontal velocity (replicated for clients).
	anim_speed = Vector2(velocity.x, velocity.z).length()
	move_and_slide()


# Cosmetic, every peer: drive the visual from the (host-authored, replicated) anim drivers. Runs on
# all peers (the host authors them in _physics_process; clients receive them via replication).
func _process(_delta: float) -> void:
	if _visual == null:
		return
	_visual.rotation.y = face_yaw
	if _visual.has_method("feed_speed"):
		_visual.feed_speed(anim_speed)


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


# ── RPC: host → all peers, cosmetic attack swing ──
# Authority RPC (not the client-owned-player `any_peer` exception): the host IS the enemy's authority,
# so it can fan this out directly. call_local so the host's own copy swings too.
@rpc("authority", "call_local", "reliable")
func play_attack_anim() -> void:
	if _visual != null and _visual.has_method("fire_oneshot"):
		_visual.fire_oneshot()
