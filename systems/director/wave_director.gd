class_name WaveDirector
extends Node

## Host-only escalating wave spawner. On a timer it spawns rings of EnemyBase around the arena,
## growing the count each wave. Everything here runs only on the host; spawning goes through
## Main.spawn_enemy() (host-authoritative), and the MultiplayerSpawner replicates each enemy to
## clients. This is deliberately a DUMB timer — the smart, stress-reactive "AI Director" pacing
## (Left 4 Dead style) is a beyond-slice concern. All knobs are @export.

@export var first_wave_delay_sec: float = 2.0
@export var time_between_waves_sec: float = 8.0
@export var base_enemies_per_wave: int = 3
@export var enemies_added_per_wave: int = 2
@export var spawn_interval_sec: float = 0.4
@export var max_alive_enemies: int = 5  # hard cap on enemies on screen at once (skip-when-full)
@export var spawn_ring_radius: float = 9.0
@export var spawn_height: float = 1.0
@export var arena_center: Vector3 = Vector3.ZERO

var _wave_index: int = 0
var _enemy_counter: int = 0


# Read-only accessor for the dev console / HUD.
func current_wave() -> int:
	return _wave_index


func _ready() -> void:
	# Clients run nothing — all spawning is host-authoritative.
	if not multiplayer.is_server():
		return
	_run_waves()


func _run_waves() -> void:
	await get_tree().create_timer(first_wave_delay_sec).timeout
	while is_inside_tree():
		_wave_index += 1
		var count := base_enemies_per_wave + enemies_added_per_wave * (_wave_index - 1)
		print("[WaveDirector] Wave %d — spawning %d enemies" % [_wave_index, count])
		for _i in count:
			_spawn_one()
			await get_tree().create_timer(spawn_interval_sec).timeout
		await get_tree().create_timer(time_between_waves_sec).timeout


func _spawn_one() -> void:
	# Skip-when-full: hold total alive enemies at the cap. As they die, spawns refill toward it.
	var enemies := get_parent().get_node_or_null("Enemies")
	if enemies and enemies.get_child_count() >= max_alive_enemies:
		return
	var angle := randf() * TAU
	var pos := arena_center + Vector3(cos(angle), 0.0, sin(angle)) * spawn_ring_radius
	pos.y = spawn_height
	# Host-assigned unique, non-numeric name so it never collides with a peer-id player name
	# and stays identical across peers (the spawn_function sets it before add_child).
	var config := {"name": "Enemy_%d" % _enemy_counter, "pos": pos}
	_enemy_counter += 1
	var main := get_parent()
	if main.has_method("spawn_enemy"):
		main.spawn_enemy(config)
