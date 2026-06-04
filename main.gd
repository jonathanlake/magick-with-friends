extends Node

var player_scene: PackedScene = preload("uid://cunquuhctdb1o")
var _hud_scene: PackedScene = preload("uid://ct7hud5x8kl3n")
# New assets — referenced by path until the editor assigns a uid.
var projectile_scene: PackedScene = preload("res://entities/projectiles/projectile.tscn")
var enemy_scene: PackedScene = preload("res://entities/enemies/enemy_base.tscn")

@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var projectile_spawner: MultiplayerSpawner = $ProjectileSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var player_spawn_position: Marker3D = find_child("PlayerSpawnPosition", true, false)

# Host-only guard so a dead player only queues one respawn.
var _respawning: Dictionary = {}


func _ready() -> void:
	add_child(_hud_scene.instantiate())

	multiplayer_spawner.spawn_function = func(data):
		var player := player_scene.instantiate() as Player
		player.name = str(data.peer_id)
		player.input_multiplayer_authority = data.peer_id
		player.player_name = data.player_name
		player.position = player_spawn_position.global_position
		return player

	# Runs on every peer with the same config, so projectile visuals match everywhere.
	projectile_spawner.spawn_function = func(data):
		var proj := projectile_scene.instantiate() as Projectile
		proj.setup(data)
		return proj

	# Same pattern for enemies — runs on every peer; host drives spawns via the WaveDirector.
	enemy_spawner.spawn_function = func(data):
		var enemy := enemy_scene.instantiate() as EnemyBase
		enemy.name = data["name"]
		enemy.position = data["pos"]
		return enemy

	if multiplayer.is_server():
		# Spawn the host's own player immediately — no RPC needed.
		multiplayer_spawner.spawn({"peer_id": multiplayer.get_unique_id(), "player_name": GameManager.player_name})
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	else:
		# Tell the host we're ready. The RPC fires only on the host (call_remote),
		# so get_remote_sender_id() is always a real peer ID, never 0.
		peer_ready.rpc_id(1, GameManager.player_name)


func _on_peer_disconnected(peer_id: int) -> void:
	var player_node := get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func peer_ready(p_name: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().size() < GameManager.config.max_players:
		multiplayer_spawner.spawn({"peer_id": peer_id, "player_name": p_name})


# ── Spell projectiles (host-authoritative) ───────────────────────────────────

## Host-only. Called by a spell's cast_on_host to spawn a replicated projectile.
func spawn_projectile(config: Dictionary) -> void:
	if multiplayer.is_server():
		projectile_spawner.spawn(config)


## Host-only. Called by the WaveDirector to spawn one replicated enemy.
func spawn_enemy(config: Dictionary) -> void:
	if multiplayer.is_server():
		enemy_spawner.spawn(config)


## Called on the host by a projectile hit. Health is host-authoritative: the host computes
## the new value and pushes it to every peer (so peers can't desync by a hit), then drives
## death + respawn.
func apply_player_damage(victim_peer: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var player := get_node_or_null(str(victim_peer)) as Player
	if player == null:
		return
	var hc := player.get_node_or_null("HealthComponent") as HealthComponent
	if hc == null or hc.current_health <= 0:
		return  # ignore hits on an already-dead player
	hc.damage(amount)
	_sync_health.rpc(victim_peer, hc.current_health)
	if hc.current_health <= 0:
		_on_player_died(victim_peer)


@rpc("authority", "call_local", "reliable")
func _sync_health(victim_peer: int, value: int) -> void:
	var player := get_node_or_null(str(victim_peer)) as Player
	if player == null:
		return
	var hc := player.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.current_health = value


func _on_player_died(victim_peer: int) -> void:
	if _respawning.has(victim_peer):
		return
	_respawning[victim_peer] = true
	_set_dead.rpc(victim_peer, true)
	await get_tree().create_timer(GameManager.config.respawn_time).timeout
	_respawn_player.rpc(victim_peer)
	_respawning.erase(victim_peer)


@rpc("authority", "call_local", "reliable")
func _set_dead(victim_peer: int, dead: bool) -> void:
	var player := get_node_or_null(str(victim_peer)) as Player
	if player:
		player.set_dead(dead)


@rpc("authority", "call_local", "reliable")
func _respawn_player(victim_peer: int) -> void:
	var player := get_node_or_null(str(victim_peer)) as Player
	if player == null:
		return
	var hc := player.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.reset()
	player.set_dead(false)
	# The victim's own machine teleports its own player (robust to authority config).
	if multiplayer.get_unique_id() == victim_peer:
		player.global_position = player_spawn_position.global_position
		player.linear_velocity = Vector3.ZERO
