extends Control
class_name NavigationHUD

## Emitted when the player requests the galaxy map. No gameplay logic here.
signal galaxy_requested


func _on_galaxy_button_pressed() -> void:
	galaxy_requested.emit()
