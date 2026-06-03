extends CanvasLayer

@onready var _debug_label: Label = $DebugPanel/MarginContainer/VBoxContainer/DebugLabel

var _player: Player = null


func _process(_delta: float) -> void:
	if not _player:
		var peer_id := str(multiplayer.get_unique_id())
		_player = get_parent().get_node_or_null(peer_id) as Player

	_update_readout()


func _update_readout() -> void:
	if not _player:
		_debug_label.text = "(no player)"
		return
	var wand := _player.get_node_or_null("WandComponent") as WandComponent
	var hc := _player.get_node_or_null("HealthComponent") as HealthComponent
	var spell_text: String = wand.current_spell_text() if wand else "?"
	var hp: int = hc.current_health if hc else 0
	_debug_label.text = "SPELL  %s\nHP     %d" % [spell_text, hp]
