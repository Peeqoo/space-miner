## Applies mining-ship action fields to an ObjectInfo dictionary.
class_name MiningShipInfoOverlay
extends RefCounted

const OVERLAY_KEYS: Array[StringName] = [
	ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP,
	ObjectInfoDictKeys.CAN_MINE_WITH_SHIP,
	ObjectInfoDictKeys.MINE_BLOCKED_REASON,
	ObjectInfoDictKeys.MINING_BUTTON_TEXT,
	ObjectInfoDictKeys.MINING_EXHAUSTED,
	ObjectInfoDictKeys.ASSIGNED_MINING_SHIP_COUNT,
	ObjectInfoDictKeys.SHOW_MINING_SHIP_STATUS,
]


static func apply(
	info: Dictionary,
	selected_node: Node,
	object_id: String,
	system_id: String,
	base_id: String,
	automation_controller: AutomationController,
	has_available_mining_ship: bool,
	mining_button_text: String,
	is_established_home_body: bool,
) -> void:
	info[ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP] = false
	info[ObjectInfoDictKeys.CAN_MINE_WITH_SHIP] = false
	info[ObjectInfoDictKeys.MINE_BLOCKED_REASON] = ""
	info[ObjectInfoDictKeys.MINING_EXHAUSTED] = false
	info[ObjectInfoDictKeys.ASSIGNED_MINING_SHIP_COUNT] = 0
	info[ObjectInfoDictKeys.SHOW_MINING_SHIP_STATUS] = false
	info[ObjectInfoDictKeys.MINING_BUTTON_TEXT] = ""

	if selected_node == null:
		return

	if selected_node is SignalMarker:
		return

	if not selected_node is SystemBody and not selected_node is PointOfInterest:
		return

	if selected_node is SystemBody and is_established_home_body:
		return

	var sys_id: String = system_id.strip_edges()
	var target_id: String = object_id.strip_edges()
	if sys_id.is_empty() or target_id.is_empty():
		return

	var economy_base_id: String = base_id.strip_edges()
	var mine_gate: Dictionary = GameSession.can_mine_object(
		sys_id,
		target_id,
		economy_base_id,
		has_available_mining_ship,
	)

	info[ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP] = bool(mine_gate.get("show_mine_button", false))
	info[ObjectInfoDictKeys.CAN_MINE_WITH_SHIP] = bool(mine_gate.get("ok", false))
	info[ObjectInfoDictKeys.MINE_BLOCKED_REASON] = str(
		mine_gate.get("blocked_reason", "")
	).strip_edges()

	var block_key: StringName = mine_gate.get("blocked_reason_key", &"")
	info[ObjectInfoDictKeys.MINING_EXHAUSTED] = (
		bool(info.get(ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP, false))
		and not bool(info.get(ObjectInfoDictKeys.CAN_MINE_WITH_SHIP, false))
		and block_key == GateUiTextDefinition.KEY_MINE_DEPLETED
	)

	var assigned_count: int = _get_assigned_mining_ship_count(automation_controller, target_id)
	info[ObjectInfoDictKeys.ASSIGNED_MINING_SHIP_COUNT] = assigned_count
	info[ObjectInfoDictKeys.SHOW_MINING_SHIP_STATUS] = (
		bool(info.get(ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP, false)) or assigned_count > 0
	)

	if bool(info.get(ObjectInfoDictKeys.SHOW_MINE_WITH_SHIP, false)):
		info[ObjectInfoDictKeys.MINING_BUTTON_TEXT] = mining_button_text.strip_edges()


static func _get_assigned_mining_ship_count(
	automation_controller: AutomationController,
	object_id: String,
) -> int:
	if object_id.is_empty() or automation_controller == null:
		return 0
	return automation_controller.get_assigned_mining_ship_count(object_id)
