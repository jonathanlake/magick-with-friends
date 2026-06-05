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
	if not ("host" in args or "join" in args):
		return

	# Autoloads initialize before the main scene loads, and Godot sets its own
	# window title after autoloads finish. Wait one frame so both the main menu
	# and the window title are fully settled before we act.
	await get_tree().process_frame

	if "host" in args:
		DisplayServer.window_set_title("HOST")
		# Host on the LEFT monitor; falls back to the top-left of a single screen.
		_place_window_on_screen(_leftmost_screen(), Vector2i(0, 0))
		GameManager.player_name = "HOST"
		NetworkManager.host_game()
		get_tree().change_scene_to_packed(_main_scene)
	elif "join" in args:
		DisplayServer.window_set_title("CLIENT")
		# Client on the MAIN (primary) monitor; falls back to a right-offset on a single screen.
		_place_window_on_screen(DisplayServer.get_primary_screen(), Vector2i(960, 0))
		GameManager.player_name = "CLIENT"
		# main_menu._on_connection_succeeded handles the scene transition.
		NetworkManager.join_game("127.0.0.1")


# Move this instance's window to the top-left of the given monitor. If there's only one
# screen (or the index is invalid), use fallback_pos so the two windows still sit side by side.
func _place_window_on_screen(screen: int, fallback_pos: Vector2i) -> void:
	if DisplayServer.get_screen_count() < 2 or screen < 0 or screen >= DisplayServer.get_screen_count():
		DisplayServer.window_set_position(fallback_pos)
		return
	DisplayServer.window_set_current_screen(screen)
	DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))


# Index of the physically leftmost monitor (smallest virtual-desktop x).
func _leftmost_screen() -> int:
	var best := 0
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_position(i).x < DisplayServer.screen_get_position(best).x:
			best = i
	return best


# Host headless, load Main, wait a few frames, and assert the host player spawned.
# Frame-based (not wall-clock) so it's deterministic under headless. Quits with code
# 0 on success, 1 on failure; the `SMOKE_OK` / `SMOKE_FAIL` print is the harness's signal.
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
	# Print evidence read LIVE from the running scene tree (not fixed strings), so a PASS is
	# self-verifying: the loaded scene's name, the host player's real node path, and that its
	# components are wired (WandComponent is added in code; HealthComponent comes from the scene).
	if player != null:
		print("SMOKE_OK: scene='%s' | host player '%s' is live | WandComponent=%s HealthComponent=%s | is_server=%s" % [
			main.name, player.get_path(), player.has_node("WandComponent"),
			player.has_node("HealthComponent"), multiplayer.is_server()])
		get_tree().quit(0)
	else:
		print("SMOKE_FAIL: scene='%s', no host player node named '%s' in the tree" % [
			(main.name if main else "<none>"), pid])
		get_tree().quit(1)
