extends Node

# uid://dxjewv468c6y2 is main.tscn — same UID used by main_menu.gd
var _main_scene: PackedScene = preload("uid://dxjewv468c6y2")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
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
		DisplayServer.window_set_position(Vector2i(0, 0))
		GameManager.player_name = "HOST"
		NetworkManager.host_game()
		get_tree().change_scene_to_packed(_main_scene)
	elif "join" in args:
		DisplayServer.window_set_title("CLIENT")
		DisplayServer.window_set_position(Vector2i(960, 0))
		GameManager.player_name = "CLIENT"
		# main_menu._on_connection_succeeded handles the scene transition.
		NetworkManager.join_game("127.0.0.1")
