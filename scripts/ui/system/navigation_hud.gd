extends Control
class_name NavigationHUD

## Emitted when the player requests the galaxy map. No gameplay logic here.
signal galaxy_requested

@onready var galaxy_button: Button = $GalaxyButton


func _ready() -> void:
	if galaxy_button == null:
		push_warning("NavigationHUD: GalaxyButton node missing.")
		return
	if not galaxy_button.pressed.is_connected(_on_galaxy_button_pressed):
		galaxy_button.pressed.connect(_on_galaxy_button_pressed)


func _on_galaxy_button_pressed() -> void:
	galaxy_requested.emit()
