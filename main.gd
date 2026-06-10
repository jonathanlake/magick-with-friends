extends Node

var player_scene: PackedScene = preload("uid://cunquuhctdb1o")
var _hud_scene: PackedScene = preload("uid://ct7hud5x8kl3n")
var _console_scene: PackedScene = preload("res://ui/console/dev_console.tscn")
# New assets — referenced by path until the editor assigns a uid.
var projectile_scene: PackedScene = preload("res://entities/projectiles/projectile.tscn")
var enemy_scene: PackedScene = preload("res://entities/enemies/enemy_base.tscn")
# main_menu.tscn — load()ed at runtime (NOT preload) to avoid a cyclic scene dependency:
# main_menu.gd preloads main.tscn, which uses this script, so preloading the menu here would
# make one of the two scenes resolve as an empty PackedScene.
const _MENU_SCENE_UID := "uid://c7c1omna7f0iq"

@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var projectile_spawner: MultiplayerSpawner = $ProjectileSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var player_spawn_position: Marker3D = find_child("PlayerSpawnPosition", true, false)

# Host-only guard so a dead player only queues one respawn.
var _respawning: Dictionary = {}
# HUD instance (kept so we can show the "host left" overlay) + one-shot leave guard.
var _hud: Node = null
var _leaving: bool = false


func _ready() -> void:
	# GameEvents is an autoload that outlives the scene; clear any count carried over from a prior
	# session before the HUD (added just below) seeds itself from it.
	GameEvents.alive_enemy_count = 0

	_hud = _hud_scene.instantiate()
	add_child(_hud)

	multiplayer_spawner.spawn_function = func(data):
		var player := player_scene.instantiate() as Player
		player.name = str(data.peer_id)
		player.input_multiplayer_authority = data.peer_id
		player.peer_id = data.peer_id
		player.player_name = data.player_name
		# Catalog indices for the random-dealt blend (host rolls them in _player_spawn_config).
		# Travel as ints so every peer rebuilds the same wand.
		player.form_idx = int(data.get("form_idx", 0))
		player.element_idx = int(data.get("element_idx", 0))
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

	# Dev console on EVERY peer. It gates itself by role: the host gets the full command set; clients
	# get only the local-safe ones (help/clear) plus a seam for future client-side commands. See
	# dev_console.gd's _HOST_ONLY gate.
	add_child(_console_scene.instantiate())

	if multiplayer.is_server():
		# Spawn the host's own player immediately — no RPC needed.
		multiplayer_spawner.spawn(_player_spawn_config(multiplayer.get_unique_id(), GameManager.player_name))
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	else:
		# Tell the host we're ready. The RPC fires only on the host (call_remote),
		# so get_remote_sender_id() is always a real peer ID, never 0.
		peer_ready.rpc_id(1, GameManager.player_name)
		# Only clients can lose the host. NetworkManager re-emits this and nulls the peer.
		NetworkManager.server_disconnected.connect(_on_server_disconnected)


func _on_peer_disconnected(peer_id: int) -> void:
	var player_node := get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()


# Client-side: the host left. Freeze the game (pause halts the per-frame RPC/spawner/synchronizer
# work that would otherwise crash against the now-null peer), show the overlay, then bail to menu.
func _on_server_disconnected() -> void:
	if _leaving:
		return
	_leaving = true
	if _hud and _hud.has_method("show_host_left"):
		_hud.show_host_left()
	get_tree().paused = true
	# process_always = true so the timer still fires while the tree is paused.
	await get_tree().create_timer(2.5, true).timeout
	get_tree().paused = false
	get_tree().change_scene_to_packed(load(_MENU_SCENE_UID))


@rpc("any_peer", "call_remote", "reliable")
func peer_ready(p_name: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	# Duplicate guard: a re-sent peer_ready would spawn a second node Godot auto-renames,
	# breaking the name-IS-peer-id contract every host lookup below relies on.
	if get_node_or_null(str(peer_id)) != null:
		return
	if multiplayer.get_peers().size() < GameManager.config.max_players:
		multiplayer_spawner.spawn(_player_spawn_config(peer_id, p_name))
	else:
		# Over capacity. The transport already caps clients at max_players - 1, so this is a
		# backstop — kick, so the peer falls back to its menu (via server_disconnected)
		# instead of sitting connected-but-playerless in a world it can't play in.
		NetworkManager.kick_peer(peer_id)


## Host-only. Builds the player spawn config, rolling a random (Form, Element) blend from the
## catalog. Indices travel to every peer in the replicated config so each rebuilds the same wand.
## (Acquisition/pickups in item 6 will later let players change this via the wand's equip-sync RPC.)
func _player_spawn_config(peer_id: int, p_name: String) -> Dictionary:
	return {
		"peer_id": peer_id,
		"player_name": p_name,
		"form_idx": randi() % SpellCatalog.form_count(),
		"element_idx": randi() % SpellCatalog.element_count(),
	}


# ── Spell projectiles (host-authoritative) ───────────────────────────────────

## Host-only. Called by a spell's cast_on_host to spawn a replicated projectile.
func spawn_projectile(config: Dictionary) -> void:
	if multiplayer.is_server():
		projectile_spawner.spawn(config)


## Host-only. Called by the WaveDirector to spawn one replicated enemy.
func spawn_enemy(config: Dictionary) -> void:
	if multiplayer.is_server():
		enemy_spawner.spawn(config)


# ── Spell-hit resolution (host-only; forwards to the Reactions node) ──────────
# Thin forwarders so projectiles call a stable Main surface (mirrors apply_player_damage /
# spawn_projectile). Reactions owns the damage routing + element reactions + cosmetic broadcasts.

func resolve_spell_hit(victim: Node, params: Dictionary, caster_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var reactions := get_node_or_null("Reactions")
	if reactions:
		reactions.apply_hit(victim, params, caster_peer)


func resolve_spell_burst(center: Vector3, radius: float, params: Dictionary, caster_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var reactions := get_node_or_null("Reactions")
	if reactions:
		reactions.apply_burst(center, radius, params, caster_peer)


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
		# Local first-person damage cue. _sync_health is only ever sent on a damage hit (respawn/
		# reset go through _respawn_player, never here), so fire it on the victim's own machine.
		# Don't compare value < current_health: the host pre-applies hc.damage() in
		# apply_player_damage before this runs, so on the host the drop is already baked in — that
		# asymmetry is exactly why the cue fired on clients but not the host.
		if multiplayer.get_unique_id() == victim_peer:
			GameEvents.emit_local_player_damaged()


func _on_player_died(victim_peer: int) -> void:
	if _respawning.has(victim_peer):
		return
	_respawning[victim_peer] = true
	_set_dead.rpc(victim_peer, true)
	await get_tree().create_timer(GameManager.config.respawn_time).timeout
	# Broadcast the authoritative spawn position so every peer can park the respawning player's
	# (decoupled) Visual at it — the owner-only body teleport below replicates ~1 RTT later.
	_respawn_player.rpc(victim_peer, player_spawn_position.global_position)
	_respawning.erase(victim_peer)


@rpc("authority", "call_local", "reliable")
func _set_dead(victim_peer: int, dead: bool) -> void:
	var player := get_node_or_null(str(victim_peer)) as Player
	if player:
		player.set_dead(dead)


@rpc("authority", "call_local", "reliable")
func _respawn_player(victim_peer: int, spawn_pos: Vector3) -> void:
	var player := get_node_or_null(str(victim_peer)) as Player
	if player == null:
		return
	var hc := player.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.reset()
	player.set_dead(false)
	# Park the decoupled remote Visual at the spawn point on every peer (no-op on the owner).
	player.respawn_visual_to(spawn_pos)
	# The victim's own machine teleports its own player (robust to authority config).
	if multiplayer.get_unique_id() == victim_peer:
		player.global_position = spawn_pos
		player.velocity = Vector3.ZERO
