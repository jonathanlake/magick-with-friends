extends CanvasLayer

## Host-only dev console (v1). Toggled with backtick. Commands to ease playtesting:
## help / start / give / players / wave / enemies / clear. `start` begins the round (the wave director
## boots paused); `give [all]` hands a random spell (acquisition stand-in). Mounted only on the host
## (see main.gd), so it is inherently
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
			_println("commands: help, start, give [all], players, wave, enemies [off|on|clear], clear")
		"clear":
			_output.clear()
		"start":
			_cmd_start()
		"give":
			_cmd_give(parts)
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


# Begin the round: un-pause the host's wave director (it boots paused via auto_start=false).
func _cmd_start() -> void:
	var main := get_parent()
	var director := main.get_node_or_null("WaveDirector")
	if director == null or not director.has_method("set_spawning"):
		_println("  no WaveDirector — can't start")
		return
	if director.has_method("is_spawning") and director.is_spawning():
		_println("  round already running")
		return
	director.set_spawning(true)
	_println("  round started — the horde is coming")


# Hand a player a random (form, element) blend — the slice's stand-in for drop-based acquisition,
# enough to playtest the random keep/swap loop without the full pickup system. `give` rerolls the
# host's own spell; `give all` rerolls every player. Reuses SpellCatalog + WandComponent's
# host-broadcast equip-sync (request_set_blend), so the change shows on every peer.
func _cmd_give(parts: PackedStringArray) -> void:
	var fc := SpellCatalog.form_count()
	var ec := SpellCatalog.element_count()
	if fc <= 0 or ec <= 0:
		_println("  spell catalog is empty")
		return
	var all := parts.size() > 1 and parts[1].to_lower() == "all"
	var n := 0
	for child in get_parent().get_children():
		var p := child as Player
		if p == null:
			continue
		if not all and p.peer_id != multiplayer.get_unique_id():
			continue
		var wand := p.get_node_or_null("WandComponent")
		if wand and wand.has_method("request_set_blend"):
			wand.request_set_blend(randi() % fc, randi() % ec)
			n += 1
	_println("  gave a random spell to %d player(s)" % n)


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
