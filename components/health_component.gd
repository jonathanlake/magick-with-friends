class_name HealthComponent
extends Node

signal died

# Slice default 100 so friendly fire is funny, not instant-death. Enemies override this.
@export var max_health: int = 100

var current_health: int


func _ready() -> void:
	current_health = max_health


func damage(amount: int):
	current_health = clamp(current_health - amount, 0, max_health)
	if current_health == 0:
		died.emit()


func reset() -> void:
	current_health = max_health
