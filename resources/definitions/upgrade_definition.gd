## Data-driven upgrade tier (Phase 5.5). Balancing lives in `.tres` files; code applies mechanics only.
class_name UpgradeDefinition
extends Resource

@export var id: StringName = &""
@export var category: StringName = &""
# Expected: "storage", "scan_drone", "mining_ship"

@export var level: int = 0
@export var title: String = ""
@export var cost: Dictionary = {}

## Level 0 is not purchasable.
@export var purchasable: bool = true

## Storage — total capacity units at this tier (-1 = unused).
@export var storage_capacity_units: int = -1

## ScanDrone — display / gameplay hints (-1 or <0 = unused).
@export var scan_speed_percent: int = -1
@export var scan_duration_multiplier: float = -1.0
@export var mining_yield_bonus_per_support_drone_percent: int = -1

## MiningShip — cargo as percent of base mission capacity (-1 = unused).
@export var cargo_capacity_percent: int = -1

## Resource layer gates — matches `ScannedResourceEntry.Layer` (0=BASIC, 1=DEEP, 2=SPECIAL).
@export var unlock_scan_layer: int = 0
@export var unlock_mining_layer: int = 0

@export var applies_to_new_jobs_only: bool = false
@export var note: String = ""

## Upgrade-specific hover copy (not global UI section labels).
@export_multiline var short_description: String = ""
## Non-numeric unlocks / special rules only (no computed stat duplicates).
@export var effect_lines: PackedStringArray = []
## Max-level special-case lines only (no computed stat duplicates).
@export var max_level_effect_lines: PackedStringArray = []

static var _effect_texts: UpgradeEffectTextDefinition = null


static func set_effect_texts(definition: UpgradeEffectTextDefinition) -> void:
	_effect_texts = definition


static func format_resource_title(resource_id: String) -> String:
	var cleaned := resource_id.strip_edges().replace("_", " ")
	if cleaned.is_empty():
		return "-"
	var words := cleaned.split(" ", false)
	var result: PackedStringArray = []
	for word in words:
		if not word.is_empty():
			result.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())
	return " ".join(result)


static func format_resource_cost_lines(p_cost: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var keys: Array = p_cost.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return str(a).to_lower() < str(b).to_lower()
	)
	for res_id: Variant in keys:
		var need := int(p_cost.get(res_id, 0))
		out.append("%s: %d" % [format_resource_title(str(res_id)), need])
	return out


static func duration_reduction_percent_from_multiplier(multiplier: float) -> int:
	if multiplier <= 0.0:
		return 0
	return int(round((1.0 - multiplier) * 100.0))


static func duration_delta_percent(current_multiplier: float, next_multiplier: float) -> int:
	if current_multiplier <= 0.0 or next_multiplier <= 0.0:
		return 0
	return int(round((1.0 - next_multiplier / current_multiplier) * 100.0))


static func _format_effect_template(template_key: String, value: Variant) -> String:
	if _effect_texts == null:
		push_warning("UpgradeDefinition: effect text templates not loaded (%s)" % template_key)
		return ""
	return _effect_texts.format_template(template_key, value)


static func _append_formatted_effect_line(
	lines: PackedStringArray,
	template_key: String,
	value: Variant
) -> void:
	var formatted := _format_effect_template(template_key, value).strip_edges()
	if formatted.is_empty():
		return
	_append_line_if_missing(lines, formatted)


## Numeric + unlock deltas for purchasable next tier (UpgradePanel preview).
static func build_delta_effect_lines(
	current: UpgradeDefinition,
	next: UpgradeDefinition
) -> PackedStringArray:
	var lines: PackedStringArray = []
	if next == null:
		return lines

	_append_resource_special_effect_lines(next.effect_lines, lines)

	match String(next.category):
		"storage":
			_append_storage_delta_lines(current, next, lines)
		"scan_drone":
			_append_scan_drone_delta_lines(current, next, lines)
		"mining_ship":
			_append_mining_ship_delta_lines(current, next, lines)

	return lines


## Final active stat lines for current tier (Max-Level hover + TopHUD).
static func build_final_effect_lines(current: UpgradeDefinition) -> PackedStringArray:
	var lines: PackedStringArray = []
	if current == null:
		return lines

	match String(current.category):
		"storage":
			_append_storage_final_lines(current, lines)
		"scan_drone":
			_append_scan_drone_final_lines(current, lines)
		"mining_ship":
			_append_mining_ship_final_lines(current, lines)

	_append_resource_special_effect_lines(current.effect_lines, lines)
	return lines


static func build_max_level_special_effect_lines(current: UpgradeDefinition) -> PackedStringArray:
	var lines: PackedStringArray = []
	if current == null:
		return lines
	_append_resource_special_effect_lines(current.max_level_effect_lines, lines)
	return lines


## Shared hover body for UpgradePanel preview/max states.
static func build_panel_hover_lines(
	current: UpgradeDefinition,
	next: UpgradeDefinition,
	has_next: bool,
	section_labels: Dictionary = {}
) -> PackedStringArray:
	var lines: PackedStringArray = []
	var cost_header := str(section_labels.get("cost", "")).strip_edges()
	var effects_header := str(section_labels.get("effects", "")).strip_edges()
	var status_header := str(section_labels.get("status", "")).strip_edges()
	var max_level_message := str(section_labels.get("max_level_message", "")).strip_edges()

	if has_next:
		if next == null:
			return lines
		var desc := next.short_description.strip_edges()
		if not desc.is_empty():
			lines.append(desc)
		if not cost_header.is_empty():
			lines.append(cost_header)
		lines.append_array(format_resource_cost_lines(next.cost))
		if not effects_header.is_empty():
			lines.append(effects_header)
		lines.append_array(build_delta_effect_lines(current, next))
		var note_next := next.note.strip_edges()
		if not note_next.is_empty():
			lines.append(note_next)
		return lines

	if current == null:
		return lines

	if not status_header.is_empty():
		lines.append(status_header)
	if not max_level_message.is_empty():
		lines.append(max_level_message)
	if not effects_header.is_empty():
		lines.append(effects_header)
	lines.append_array(build_final_effect_lines(current))
	lines.append_array(build_max_level_special_effect_lines(current))
	var note_cur := current.note.strip_edges()
	if not note_cur.is_empty():
		lines.append(note_cur)
	return lines


## Current-tier effect block for TopHUD hover (final active values, no delta).
static func append_current_tier_effect_block(
	target: Array,
	current: UpgradeDefinition,
	_at_max_level: bool,
	effects_section: String = ""
) -> void:
	if current == null:
		return
	var effects_header := effects_section.strip_edges()
	if not effects_header.is_empty():
		target.append(effects_header)
	for line: String in build_final_effect_lines(current):
		target.append(line)
	for line: String in build_max_level_special_effect_lines(current):
		target.append(line)
	var note_text := current.note.strip_edges()
	if not note_text.is_empty():
		target.append(note_text)


static func _append_storage_delta_lines(
	current: UpgradeDefinition,
	next: UpgradeDefinition,
	lines: PackedStringArray
) -> void:
	if current == null:
		return
	if current.storage_capacity_units <= 0 or next.storage_capacity_units <= 0:
		return
	var delta_percent := int(
		round(
			(float(next.storage_capacity_units) / float(current.storage_capacity_units) - 1.0) * 100.0
		)
	)
	if delta_percent != 0:
		_append_formatted_effect_line(lines, "storage_capacity_delta", delta_percent)


static func _append_storage_final_lines(def: UpgradeDefinition, lines: PackedStringArray) -> void:
	if def.storage_capacity_units > 0:
		_append_formatted_effect_line(lines, "storage_capacity_final", def.storage_capacity_units)


static func _append_scan_drone_delta_lines(
	current: UpgradeDefinition,
	next: UpgradeDefinition,
	lines: PackedStringArray
) -> void:
	if current == null:
		return

	if current.scan_duration_multiplier > 0.0 and next.scan_duration_multiplier > 0.0:
		var duration_delta := duration_delta_percent(
			current.scan_duration_multiplier,
			next.scan_duration_multiplier
		)
		if duration_delta > 0:
			_append_formatted_effect_line(lines, "scan_duration_delta", duration_delta)

	if (
		current.mining_yield_bonus_per_support_drone_percent >= 0
		and next.mining_yield_bonus_per_support_drone_percent >= 0
	):
		var support_delta := (
			next.mining_yield_bonus_per_support_drone_percent
			- current.mining_yield_bonus_per_support_drone_percent
		)
		if support_delta > 0:
			_append_formatted_effect_line(lines, "scan_support_delta", support_delta)


static func _append_scan_drone_final_lines(def: UpgradeDefinition, lines: PackedStringArray) -> void:
	if def.scan_duration_multiplier > 0.0:
		var duration_reduction := duration_reduction_percent_from_multiplier(def.scan_duration_multiplier)
		if duration_reduction > 0:
			_append_formatted_effect_line(lines, "scan_duration_final", duration_reduction)

	if def.mining_yield_bonus_per_support_drone_percent >= 0:
		_append_formatted_effect_line(
			lines,
			"scan_support_final",
			def.mining_yield_bonus_per_support_drone_percent
		)


static func _append_mining_ship_delta_lines(
	current: UpgradeDefinition,
	next: UpgradeDefinition,
	lines: PackedStringArray
) -> void:
	if current == null:
		return

	if current.cargo_capacity_percent >= 0 and next.cargo_capacity_percent >= 0:
		var cargo_delta := next.cargo_capacity_percent - current.cargo_capacity_percent
		if cargo_delta > 0:
			_append_formatted_effect_line(lines, "cargo_delta", cargo_delta)


static func _append_mining_ship_final_lines(def: UpgradeDefinition, lines: PackedStringArray) -> void:
	if def.cargo_capacity_percent >= 0:
		_append_formatted_effect_line(lines, "cargo_final", def.cargo_capacity_percent)


static func _append_resource_special_effect_lines(
	source_lines: PackedStringArray,
	target: PackedStringArray
) -> void:
	for line: String in source_lines:
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		_append_line_if_missing(target, trimmed)


static func _append_line_if_missing(target: PackedStringArray, line: String) -> void:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return
	if target.has(trimmed):
		return
	target.append(trimmed)
