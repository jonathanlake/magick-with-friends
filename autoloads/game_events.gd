extends Node

signal enemy_died
signal enemy_count_changed(count: int)

# Host-and-client-consistent live enemy count. Enemies register/unregister themselves on every peer
# (MultiplayerSpawner spawn and queue_free both replicate), so this stays in sync everywhere the HUD
# shows it — no system has to reach across the tree and poll the "Enemies" node's child count.
var alive_enemy_count: int = 0


func emit_enemy_died():
	enemy_died.emit()


func register_enemy() -> void:
	alive_enemy_count += 1
	enemy_count_changed.emit(alive_enemy_count)


func unregister_enemy() -> void:
	alive_enemy_count = max(0, alive_enemy_count - 1)
	enemy_count_changed.emit(alive_enemy_count)
