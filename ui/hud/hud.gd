extends CanvasLayer

@onready var _debug_label: Label = $DebugPanel/MarginContainer/VBoxContainer/DebugLabel
@onready var _death_overlay: ColorRect = $DeathOverlay
@onready var _death_label: Label = $DeathLabel
@onready var _fps_label: Label = $FpsPanel/FpsLabel

var _player: Player = null
var _was_dead: bool = false


func _process(_delta: float) -> void:
	if not _player:
		var peer_id := str(multiplayer.get_unique_id())
		_player = get_parent().get_node_or_null(peer_id) as Player

	_fps_label.text = "FPS %d" % int(Engine.get_frames_per_second())
	_update_readout()
	_update_death_feedback()


func _update_readout() -> void:
	# Counts are computed on every peer (enemies replicate to all; peer list is the same
	# everywhere) and shown even before the local player resolves.
	var enemies := get_parent().get_node_or_null("Enemies")
	var enemy_count: int = enemies.get_child_count() if enemies else 0
	var player_count: int = multiplayer.get_peers().size() + 1
	var counts := "ENEMIES %d\nPLAYERS %d" % [enemy_count, player_count]

	if not _player:
		_debug_label.text = "(no player)\n%s" % counts
		return
	var wand := _player.get_node_or_null("WandComponent") as WandComponent
	var hc := _player.get_node_or_null("HealthComponent") as HealthComponent
	var spell_text: String = wand.current_spell_text() if wand else "?"
	var hp: int = hc.current_health if hc else 0
	_debug_label.text = "SPELL =  %s\nHP     %d\n%s" % [spell_text, hp, counts]


# Fades the local player's screen to black on death, back on respawn (cosmetic, local only).
func _update_death_feedback() -> void:
	if not _player:
		return
	var dead := _player.is_dead()
	if dead == _was_dead:
		return
	_was_dead = dead
	if dead:
		_death_label.visible = true
		create_tween().tween_property(_death_overlay, "modulate:a", 0.85, 0.25)
	else:
		_death_label.visible = false
		create_tween().tween_property(_death_overlay, "modulate:a", 0.0, 0.4)
