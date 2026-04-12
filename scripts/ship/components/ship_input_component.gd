extends RefCounted
class_name ShipInputComponent

func get_input() -> Dictionary:
	return {
		"turn": Input.get_axis("turn_left", "turn_right"),
		"thrust": Input.is_action_pressed("thrust"),
		"brake": Input.is_action_pressed("brake"),
		"stabilize": Input.is_action_pressed("stabilize"),
		"burst": Input.is_action_just_pressed("burst")
	}
