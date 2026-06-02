extends CanvasLayer

@onready var _debug_label: Label = $DebugPanel/MarginContainer/VBoxContainer/DebugLabel
@onready var _primary_bar: ProgressBar = $DebugPanel/MarginContainer/VBoxContainer/PrimaryBar
@onready var _bonus_bar: ProgressBar = $DebugPanel/MarginContainer/VBoxContainer/BonusBar

var _player: Player = null


func _process(_delta: float) -> void:
	if not _player:
		var peer_id := str(multiplayer.get_unique_id())
		_player = get_parent().get_node_or_null(peer_id) as Player

	_update_debug()
	_update_stamina()


func _update_debug() -> void:
	var lines: Array[String] = []

	lines.append("── INPUTS ──")
	lines.append("GRAB   %s" % _action_glyph("grab"))
	lines.append("JUMP   %s" % _action_glyph("jump"))
	lines.append("SPRINT %s" % _action_glyph("sprint"))
	lines.append("ATTACK %s" % _action_glyph("attack"))
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	lines.append("MOVE   (%.2f, %.2f)" % [mv.x, mv.y])

	lines.append("")
	lines.append("── STATE ──")
	if _player:
		lines.append("CLIMBING  %s" % ("YES" if _player._is_climbing else "NO"))
		lines.append("GROUNDED  %s" % ("YES" if _player._ground_check.is_colliding() else "NO"))
		lines.append("WALL DET  %s" % ("YES" if _player._wall_detected else "NO"))
		var n := _player._climb_normal
		lines.append("NORMAL   (%.1f, %.1f, %.1f)" % [n.x, n.y, n.z])
	else:
		lines.append("(no player)")

	_debug_label.text = "\n".join(lines)


func _update_stamina() -> void:
	if not _player or not _player._stamina:
		return
	var s: StaminaComponent = _player._stamina
	_primary_bar.max_value = s.max_primary
	_primary_bar.value = s.primary
	_bonus_bar.max_value = s.max_bonus
	_bonus_bar.value = s.bonus


func _action_glyph(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	return "■" if Input.is_action_pressed(action) else "□"
