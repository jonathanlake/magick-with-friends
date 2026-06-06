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


func _exit_tree() -> void:
	# If the console is freed while open (e.g. the host returns to menu mid-command), clear the
	# global input-suspend flag so the next session doesn't start with movement/look frozen.
	if _open:
		GameManager.console_open = false


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
			_println("commands: help, players, wave, enemies [off|on|clear], clear")
		"clear":
			_output.clear()
		"players":
			_cmd_players()
		"wave":
			_cmd_wave()
		"enemies":
			_cmd_enemies(parts)
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
	var wave_txt: String = str(director.current_wave()) if director and director.has_method("current_wave") else "?"
	_println("  wave %s, %d enemies alive" % [wave_txt, GameEvents.alive_enemy_count])


# enemies off  -> pause wave spawning + clear the living. enemies on -> resume. enemies clear -> just clear.
func _cmd_enemies(parts: PackedStringArray) -> void:
	var main := get_parent()
	var director := main.get_node_or_null("WaveDirector")
	var arg: String = parts[1].to_lower() if parts.size() > 1 else ""
	match arg:
		"off":
			if director and director.has_method("set_spawning"):
				director.set_spawning(false)
			_println("  enemies OFF — spawning paused, cleared %d" % _clear_enemies(main))
		"on":
			if director and director.has_method("set_spawning"):
				director.set_spawning(true)
			_println("  enemies ON — spawning resumed")
		"clear":
			_println("  cleared %d enemies (spawning unchanged)" % _clear_enemies(main))
		_:
			var state := "?"
			if director and director.has_method("is_spawning"):
				state = "on" if director.is_spawning() else "off"
			_println("  usage: enemies off | on | clear  (spawning %s, %d alive)" % [state, GameEvents.alive_enemy_count])


# Free every spawned enemy (host-authoritative; queue_free replicates the removal to clients, and each
# enemy's _exit_tree unregisters it from the live count). Returns how many were cleared.
func _clear_enemies(main: Node) -> int:
	var container := main.get_node_or_null("Enemies")
	if container == null:
		return 0
	var n := 0
	for e in container.get_children():
		e.queue_free()
		n += 1
	return n


func _println(s: String) -> void:
	_output.add_text(s + "\n")
