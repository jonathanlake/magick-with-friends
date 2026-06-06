extends Node

# uid://dxjewv468c6y2 is main.tscn — same UID used by main_menu.gd
var _main_scene: PackedScene = preload("uid://dxjewv468c6y2")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()

	# Headless gameplay smoke test (Tier 1): `-- smoke`. Boots a host into Main, verifies
	# the host player spawned, prints a PASS/FAIL marker, and quits. See tools/smoke-test.sh.
	if "smoke" in args:
		_run_smoke()
		return

	if not "debug_autostart" in args:
		return
	# Role keyword: "host"/"server" start the host, "join"/"client" connect to it. The aliases
	# exist so the intuitive word (matching the HOST/CLIENT window titles) just works too.
	var is_host := "host" in args or "server" in args
	var is_client := "join" in args or "client" in args
	if not (is_host or is_client):
		return

	# Autoloads initialize before the main scene loads, and Godot sets its own
	# window title after autoloads finish. Wait one frame so both the main menu
	# and the window title are fully settled before we act.
	await get_tree().process_frame

	if is_host:
		DisplayServer.window_set_title("HOST")
		# Host on the LEFT monitor; falls back to the top-left of a single screen.
		_place_window_on_screen(_leftmost_screen(), Vector2i(0, 0))
		GameManager.player_name = "HOST"
		NetworkManager.host_game()
		get_tree().change_scene_to_packed(_main_scene)
	elif is_client:
		DisplayServer.window_set_title("CLIENT")
		# Client on the MAIN (primary) monitor; falls back to a right-offset on a single screen.
		_place_window_on_screen(DisplayServer.get_primary_screen(), Vector2i(960, 0))
		GameManager.player_name = "CLIENT"
		# main_menu._on_connection_succeeded handles the scene transition.
		NetworkManager.join_game("127.0.0.1")


# Move this instance's window onto the given monitor and maximize it there. Maximizing (rather
# than positioning a native-size window flush to the monitor's top-left, which pushes the Windows
# title bar off-screen and looks frameless) fills the screen while keeping a usable, movable title
# bar. Falls back to a simple windowed offset when there's only one screen.
func _place_window_on_screen(screen: int, fallback_pos: Vector2i) -> void:
	if DisplayServer.get_screen_count() < 2 or screen < 0 or screen >= DisplayServer.get_screen_count():
		DisplayServer.window_set_position(fallback_pos)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)  # ensure not maximized before moving
	DisplayServer.window_set_current_screen(screen)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


# Index of the physically leftmost monitor (smallest virtual-desktop x).
func _leftmost_screen() -> int:
	var best := 0
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_position(i).x < DisplayServer.screen_get_position(best).x:
			best = i
	return best


# Host headless, load Main, wait a few frames, and assert BOTH the host player AND the enemy
# subsystem are live + wired. Frame-based (not wall-clock) so it's deterministic under headless.
# Quits with code 0 on success, 1 on failure; the `SMOKE_OK` / `SMOKE_FAIL` print is the harness's
# signal. The enemy check is deliberate: the wave director boots paused (auto_start=false), so
# without spawning one here the gate would never exercise enemy spawn / AI / animation at all.
func _run_smoke() -> void:
	await get_tree().process_frame
	GameManager.player_name = "SMOKE_HOST"
	NetworkManager.host_game()
	get_tree().change_scene_to_packed(_main_scene)
	for _i in 30:
		await get_tree().process_frame
	var main := get_tree().current_scene
	var pid := str(multiplayer.get_unique_id())
	var player: Node = main.get_node_or_null(pid) if main else null
	if player == null:
		print("SMOKE_FAIL: scene='%s', no host player node named '%s' in the tree" % [
			(str(main.name) if main else "<none>"), pid])
		get_tree().quit(1)
		return

	# Exercise the enemy path (spawn one directly — the director is paused at boot).
	var enemy_report: String = await _smoke_check_enemy(main)
	if enemy_report.begins_with("FAIL"):
		print("SMOKE_FAIL: enemy subsystem — %s" % enemy_report)
		get_tree().quit(1)
		return

	# Evidence read LIVE from the running tree (not fixed strings), so PASS is self-verifying.
	print("SMOKE_OK: scene='%s' | host player '%s' is live | WandComponent=%s HealthComponent=%s | enemy: %s | is_server=%s" % [
		main.name, player.get_path(), player.has_node("WandComponent"),
		player.has_node("HealthComponent"), enemy_report, multiplayer.is_server()])
	get_tree().quit(0)


# Spawn one enemy via Main's host spawn path and confirm it's live with its AnimationTree active.
# Returns a short evidence string, or "FAIL: <why>". Host-driven only (no input).
func _smoke_check_enemy(main: Node) -> String:
	if not main.has_method("spawn_enemy"):
		return "FAIL: Main has no spawn_enemy()"
	main.spawn_enemy({"name": "Enemy_smoke", "pos": Vector3(3.0, 1.0, 0.0)})
	for _i in 8:
		await get_tree().physics_frame
	var enemies := main.get_node_or_null("Enemies")
	var enemy: Node = enemies.get_child(0) if enemies and enemies.get_child_count() > 0 else null
	if enemy == null:
		return "FAIL: no enemy spawned under Main/Enemies"
	var tree := enemy.get_node_or_null("Visual/AnimationTree") as AnimationTree
	if tree == null:
		return "FAIL: enemy Visual/AnimationTree missing"
	if not tree.active:
		return "FAIL: enemy AnimationTree not active (LocomotionAnimator didn't wire)"
	return "'%s' spawned, AnimationTree active" % enemy.name
