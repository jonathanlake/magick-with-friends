extends Control

var main_scene: PackedScene = preload("uid://dxjewv468c6y2")

@onready var name_input: LineEdit = $VBoxContainer/NameLineEdit
@onready var ip_input: LineEdit = $VBoxContainer/LineEdit
@onready var host_button: Button = $VBoxContainer/HBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/HBoxContainer/JoinButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

const JOIN_TIMEOUT_SEC := 5.0

var _connecting: bool = false
var _attempt_token: int = 0  # invalidates stale timeout timers from earlier attempts


func _ready() -> void:
	# The menu always needs a cursor — release any capture left over from in-game
	# (the player captures the mouse for FP look; returning here must restore it).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	name_input.text_changed.connect(_on_name_changed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	host_button.disabled = true
	join_button.disabled = true


func _on_name_changed(new_text: String) -> void:
	var has_name := not new_text.strip_edges().is_empty()
	host_button.disabled = not has_name
	join_button.disabled = not has_name


func _on_host_pressed() -> void:
	GameManager.player_name = name_input.text.strip_edges()
	NetworkManager.host_game()
	get_tree().change_scene_to_packed(main_scene)


func _on_join_pressed() -> void:
	GameManager.player_name = name_input.text.strip_edges()
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"

	var ip := address
	var port := NetworkManager.DEFAULT_PORT
	if ":" in address:
		var parts := address.split(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = parts[1].to_int()

	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Connecting…"
	_connecting = true
	_attempt_token += 1
	var token := _attempt_token
	NetworkManager.join_game(ip, port)
	# Bounded fallback: ENet's connection_failed can be slow/unreliable for a dead address.
	get_tree().create_timer(JOIN_TIMEOUT_SEC).timeout.connect(_on_join_timeout.bind(token))


func _on_join_timeout(token: int) -> void:
	# Ignore stale timers (a newer attempt) or an attempt already resolved.
	if token != _attempt_token or not _connecting:
		return
	NetworkManager.disconnect_game()  # cancel the half-open peer
	_fail_connection("Could not connect to a host.")


func _on_connection_succeeded() -> void:
	_connecting = false
	get_tree().change_scene_to_packed(main_scene)


func _on_connection_failed() -> void:
	if not _connecting:
		return  # already handled by the timeout fallback
	_fail_connection("Could not connect to a host.")


func _fail_connection(message: String) -> void:
	_connecting = false
	status_label.text = message
	var has_name := not name_input.text.strip_edges().is_empty()
	host_button.disabled = not has_name
	join_button.disabled = not has_name
