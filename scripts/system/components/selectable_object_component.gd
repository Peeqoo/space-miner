## Reusable selection behavior for clickable objects.
## Handles selection ring visibility and click collision sizing.
class_name SelectableObjectComponent
extends RefCounted


# --------------------------------------------------
# State
# --------------------------------------------------

var is_selected: bool = false
var selection_ring_radius: float = 28.0


# --------------------------------------------------
# Click Area Setup
# --------------------------------------------------

func setup_click_area(click_area: Area2D, click_collision: CollisionShape2D, callable: Callable) -> void:
	if click_area == null or click_collision == null:
		return

	click_area.input_pickable = true

	if not click_area.input_event.is_connected(callable):
		click_area.input_event.connect(callable)

	update_click_shape(click_collision)


# --------------------------------------------------
# Selection
# --------------------------------------------------

func set_selected(selection_ring: Node2D, value: bool) -> void:
	is_selected = value

	if selection_ring != null:
		selection_ring.visible = value


func set_selection_ring_radius(selection_ring: Node2D, radius: float) -> void:
	selection_ring_radius = radius

	if selection_ring != null:
		selection_ring.set("radius", selection_ring_radius)


func update_click_shape(click_collision: CollisionShape2D) -> void:
	if click_collision == null:
		return

	var shape := CircleShape2D.new()
	shape.radius = max(selection_ring_radius, 12.0)
	click_collision.shape = shape
