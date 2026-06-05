extends CanvasLayer

@onready var _debug_label: Label = $DebugPanel/MarginContainer/VBoxContainer/DebugLabel
@onready var _death_overlay: ColorRect = $DeathOverlay
@onready var _death_label: Label = $DeathLabel
@onready var _fps_label: Label = $FpsPanel/FpsLabel
@onready var _disconnect_overlay: ColorRect = $DisconnectOverlay
@onready var _disconnect_label: Label = $DisconnectOverlay/DisconnectLabel

var _player: Player = null
var _wand: WandComponent = null
var _hc: HealthComponent = null
var _was_dead: bool = false
var _readout_accum: float = 1.0  # > interval, so the first frame draws the readout immediately
var _enemy_count: int = 0

const _READOUT_INTERVAL_SEC := 0.25


func _ready() -> void:
	# Live enemy count comes from the event bus, not a per-frame poll of Main's "Enemies" node.
	_enemy_count = GameEvents.alive_enemy_count
	GameEvents.enemy_count_changed.connect(_on_enemy_count_changed)


func _on_enemy_count_changed(count: int) -> void:
	_enemy_count = count


func _process(delta: float) -> void:
	if not _player:
		var peer_id := str(multiplayer.get_unique_id())
		_player = get_parent().get_node_or_null(peer_id) as Player
		if _player:
			# Cache the per-player nodes once — they never move relative to the player, so there's
			# no reason to re-resolve + cast them every frame.
			_wand = _player.get_node_or_null("WandComponent") as WandComponent
			_hc = _player.get_node_or_null("HealthComponent") as HealthComponent

	# Throttle the text readout (incl. FPS, which only changes ~1x/sec) instead of reformatting
	# and reassigning the whole label string every frame.
	_readout_accum += delta
	if _readout_accum >= _READOUT_INTERVAL_SEC:
		_readout_accum = 0.0
		_update_readout()

	# Death feedback stays per-frame: it's event-driven on the is_dead() change and early-returns
	# when unchanged, so it must stay responsive (and is cheap).
	_update_death_feedback()


func _update_readout() -> void:
	# Counts are consistent on every peer (enemy count is bus-tracked and replicates; the peer list
	# is the same everywhere) and shown even before the local player resolves.
	var player_count: int = multiplayer.get_peers().size() + 1
	_fps_label.text = "FPS %d" % int(Engine.get_frames_per_second())
	var counts := "ENEMIES %d\nPLAYERS %d" % [_enemy_count, player_count]

	if not _player:
		_debug_label.text = "(no player)\n%s" % counts
		return
	var spell_text: String = _wand.current_spell_text() if _wand else "?"
	var hp: int = _hc.current_health if _hc else 0
	_debug_label.text = "SPELL =  %s\nHP     %d\n%s" % [spell_text, hp, counts]


# Shown when the host leaves. The disconnect overlay is PROCESS_MODE_ALWAYS, so its fade still
# animates even though the caller pauses the tree right after (crash-safe shutdown).
func show_host_left() -> void:
	_fade_overlay(_disconnect_overlay, _disconnect_label, 1.0, 0.4, true)


# Fades the local player's screen to black on death, back on respawn (cosmetic, local only).
func _update_death_feedback() -> void:
	if not _player:
		return
	var dead := _player.is_dead()
	if dead == _was_dead:
		return
	_was_dead = dead
	if dead:
		_fade_overlay(_death_overlay, _death_label, 0.85, 0.25, true)
	else:
		_fade_overlay(_death_overlay, _death_label, 0.0, 0.4, false)


# Shared overlay fade: toggle the label and tween the overlay's alpha. The tween is bound to the
# overlay node (not the HUD), so a PROCESS_MODE_ALWAYS overlay still animates while the tree is paused.
func _fade_overlay(overlay: ColorRect, label: Label, target_alpha: float, dur: float, label_visible: bool) -> void:
	label.visible = label_visible
	overlay.create_tween().tween_property(overlay, "modulate:a", target_alpha, dur)
