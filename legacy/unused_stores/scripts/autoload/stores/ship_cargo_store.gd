class_name ShipCargoStore
extends RefCounted

var items: Dictionary = {}
var capacity: int = 50


func get_used() -> int:
	var total := 0

	for amount in items.values():
		total += int(amount)

	return total


func get_capacity() -> int:
	return capacity


func get_free() -> int:
	return max(capacity - get_used(), 0)


func get_items() -> Dictionary:
	return items.duplicate(true)


func add_item(item_id: String, amount: int) -> int:
	if item_id.is_empty() or amount <= 0:
		return 0

	var free_space := get_free()
	var added: int = mini(amount, free_space)

	if added <= 0:
		return 0

	items[item_id] = int(items.get(item_id, 0)) + added
	return added


func remove_item(item_id: String, amount: int) -> int:
	if item_id.is_empty() or amount <= 0:
		return 0

	var current := int(items.get(item_id, 0))
	var removed: int = mini(current, amount)

	if removed <= 0:
		return 0

	var remaining := current - removed

	if remaining <= 0:
		items.erase(item_id)
	else:
		items[item_id] = remaining

	return removed


func clear() -> void:
	items.clear()


func set_capacity(new_capacity: int) -> void:
	capacity = maxi(new_capacity, 0)
