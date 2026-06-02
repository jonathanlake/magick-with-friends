class_name PlayerInputSynchronizerComponent
extends MultiplayerSynchronizer

var movement_vector: Vector2 = Vector2.ZERO
var is_attacked_pressed: bool
var is_jump_pressed: bool
var is_grab_pressed: bool
var is_sprint_pressed: bool

func _process(_delta: float):
	if is_multiplayer_authority():
		gather_input()


func gather_input():
	movement_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_attacked_pressed = Input.is_action_pressed("attack")
	is_jump_pressed = Input.is_action_pressed("jump")
	is_grab_pressed = Input.is_action_pressed("grab")
	is_sprint_pressed = Input.is_action_pressed("sprint")
