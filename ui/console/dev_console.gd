extends CanvasLayer

## Host-only dev console (v1). Toggled with backtick. Read-only commands to ease playtesting:
## help / players / wave / clear. Mounted only on the host (see main.gd), so it is inherently
## host-only. While open it sets GameManager.console_open (suspends the host's player input —
## look/move/cast) and frees the mouse; the world keeps running for everyone (no pause).

@onready var _panel: Control = $Panel
@onready var _output: RichTextLabel = $Panel/Margin/VBox/Output
@onready var _line_edit: LineEdit = $Panel/Margin/VBox/Input

var _open: bool = false


func _ready() -> void:
	_panel.visible = false
	_line_edit.text_submitted.connect(_on_submit)
	_println("Dev console ready — type 'help'.")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		_toggle()
		get_viewport().set_input_as_handled()  # don't let backtick reach the LineEdit


func _toggle() -> void:
	_open = not _open
	_panel.visible = _open
	GameManager.console_open = _open
	if _open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_line_edit.clear()
		_line_edit.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_submit(text: String) -> void:
	var line := text.strip_edges()
	_line_edit.clear()
	if not line.is_empty():
		_println("> " + line)
		_run(line)
	# The field stays in edit mode after Enter via the LineEdit's keep_editing_on_text_submit
	# property (set in dev_console.tscn) — no focus juggling needed.


func _run(line: String) -> void:
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	match cmd:
		"help":
			_println("commands: help, players, wave, clear")
		"clear":
			_output.clear()
		"players":
			_cmd_players()
		"wave":
			_cmd_wave()
		_:
			_println("unknown command: %s (try help)" % cmd)


func _cmd_players() -> void:
	var main := get_parent()
	var count := 0
	for child in main.get_children():
		if child is Player:
			count += 1
			_println("  %s: %s" % [child.name, child.player_name])
	if count == 0:
		_println("  (no players)")


func _cmd_wave() -> void:
	var main := get_parent()
	var director := main.get_node_or_null("WaveDirector")
	var enemies := main.get_node_or_null("Enemies")
	var wave_txt: String = str(director.current_wave()) if director and director.has_method("current_wave") else "?"
	var alive: int = enemies.get_child_count() if enemies else 0
	_println("  wave %s, %d enemies alive" % [wave_txt, alive])


func _println(s: String) -> void:
	_output.add_text(s + "\n")
