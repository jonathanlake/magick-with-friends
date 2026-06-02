## Transport contract — read before adding any connection code.
##
## The rest of the codebase calls ONLY these three functions:
##   NetworkManager.host_game()
##   NetworkManager.join_game(ip)
##   NetworkManager.disconnect_game()
##
## All ENet (or future Steam / relay) code lives exclusively in host_game() and
## join_game(). Every other file stays transport-agnostic. To swap transports:
##   1. Replace the two lines inside host_game() / join_game() that create the peer.
##   2. Touch nothing else.
##
## Example future swap (Steam):
##   func host_game(...) -> void:
##       var peer := SteamMultiplayerPeer.new()
##       peer.create_host(GameManager.config.max_players)
##       multiplayer.multiplayer_peer = peer
##
## The signal layer (multiplayer.*) is above the transport and stays identical
## across ENet / Steam / WebRTC, so all signal wiring here is reusable.

extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

## Client: fired when connection to the server is established.
signal connection_succeeded
## Client: fired when the connection attempt fails.
signal connection_failed
## Client: fired when the server closes the connection.
signal server_disconnected

## All peers: fired when any remote peer joins the session.
signal peer_connected(peer_id: int)
## All peers: fired when any remote peer leaves the session.
signal peer_disconnected(peer_id: int)

# ── Config ────────────────────────────────────────────────────────────────────

const DEFAULT_PORT := 3000

# ── Public API ────────────────────────────────────────────────────────────────

func host_game(port: int = DEFAULT_PORT) -> void:
	# ── ENet transport ───────────────────────────────────────────────────────
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port) != OK:
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	# ────────────────────────────────────────────────────────────────────────


func join_game(ip: String, port: int = DEFAULT_PORT) -> void:
	# ── ENet transport ───────────────────────────────────────────────────────
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	# ────────────────────────────────────────────────────────────────────────


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

# ── Internal signal routing ───────────────────────────────────────────────────

func _ready() -> void:
	multiplayer.peer_connected.connect(func(id): peer_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id): peer_disconnected.emit(id))
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit(); disconnect_game())
	multiplayer.server_disconnected.connect(func(): server_disconnected.emit(); disconnect_game())
