extends Node

var player_scene: PackedScene = preload("uid://cunquuhctdb1o")
var _hud_scene: PackedScene = preload("uid://ct7hud5x8kl3n")

@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var player_spawn_position: Marker3D = find_child("PlayerSpawnPosition", true, false)


func _ready() -> void:
	add_child(_hud_scene.instantiate())

	multiplayer_spawner.spawn_function = func(data):
		var player := player_scene.instantiate() as Player
		player.name = str(data.peer_id)
		player.input_multiplayer_authority = data.peer_id
		player.player_name = data.player_name
		player.position = player_spawn_position.global_position
		return player

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
