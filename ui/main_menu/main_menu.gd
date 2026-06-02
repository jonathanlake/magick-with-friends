extends Control

var main_scene: PackedScene = preload("uid://dxjewv468c6y2")

@onready var name_input: LineEdit = $VBoxContainer/NameLineEdit
@onready var ip_input: LineEdit = $VBoxContainer/LineEdit
@onready var host_button: Button = $VBoxContainer/HBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/HBoxContainer/JoinButton


func _ready() -> void:
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

	join_button.disabled = true
	NetworkManager.join_game(ip, port)


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_packed(main_scene)


func _on_connection_failed() -> void:
	var has_name := not name_input.text.strip_edges().is_empty()
	join_button.disabled = not has_name
