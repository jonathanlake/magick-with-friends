class_name StaminaComponent
extends Node

signal depleted

@export var max_primary: float = 100.0
@export var max_bonus: float = 30.0
@export var primary_regen_rate: float = 15.0  # units per second, only while grounded
@export var bonus_regen_rate: float = 5.0     # units per second, slower than primary

var primary: float
var bonus: float

var _depleted_emitted: bool = false


func _ready() -> void:
	primary = max_primary
	bonus = max_bonus


func drain(amount: float) -> void:
	if primary > 0.0:
		primary = maxf(0.0, primary - amount)
	else:
		bonus = maxf(0.0, bonus - amount)
	if is_exhausted() and not _depleted_emitted:
		_depleted_emitted = true
		depleted.emit()


func regen(delta: float) -> void:
	primary = minf(max_primary, primary + primary_regen_rate * delta)
	bonus = minf(max_bonus, bonus + bonus_regen_rate * delta)
	if not is_exhausted():
		_depleted_emitted = false


func is_exhausted() -> bool:
	return primary <= 0.0 and bonus <= 0.0
