extends Node

signal enemy_died
signal enemy_count_changed(count: int)
## Local-only UI cue: the LOCAL player's HP just dropped (host-confirmed). Fired only on the
## victim's own machine. Drives the first-person damage screen-flash; audio/rumble can hook in too.
signal local_player_damaged

# Host-and-client-consistent live enemy count. Enemies register/unregister themselves on every peer
# (MultiplayerSpawner spawn and queue_free both replicate), so this stays in sync everywhere the HUD
# shows it — no system has to reach across the tree and poll the "Enemies" node's child count.
var alive_enemy_count: int = 0


func emit_enemy_died():
	enemy_died.emit()


# Emit helper so the signal is fired from within its declaring class (clears the UNUSED_SIGNAL
# warning) and callers have one stable entry point. Fired by the host on the victim's own machine.
func emit_local_player_damaged() -> void:
	local_player_damaged.emit()


func register_enemy() -> void:
	alive_enemy_count += 1
	enemy_count_changed.emit(alive_enemy_count)


func unregister_enemy() -> void:
	alive_enemy_count = max(0, alive_enemy_count - 1)
	enemy_count_changed.emit(alive_enemy_count)
