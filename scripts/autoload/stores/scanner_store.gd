class_name ScannerStore
extends RefCounted

const SCANNER_BASIC := "basic"
const SCANNER_DEEP := "deep"
const SCANNER_SPECIAL := "special"

var active_tier: String = SCANNER_BASIC


func get_active_tier() -> String:
	return active_tier


func set_active_tier(scanner_tier: String) -> void:
	if scanner_tier not in [SCANNER_BASIC, SCANNER_DEEP, SCANNER_SPECIAL]:
		return

	active_tier = scanner_tier
