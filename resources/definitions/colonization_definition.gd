## Data-driven colonization operation balancing (Phase 6.6d).
class_name ColonizationDefinition
extends Resource

@export var id: String = "default"
@export var operation_duration_ms: int = 60000
@export var allow_auto_complete: bool = false

## UI labels for colonization operation status (not global section captions).
@export var pending_status_format: String = "Läuft %ds"
@export var ready_status_label: String = "Bereit zur Ankunft"
## Shown when timer elapsed and `allow_auto_complete` is false (manual / dev complete).
@export var awaiting_confirmation_status_label: String = "Awaiting confirmation"
@export var completed_status_label: String = ""
@export var cancelled_status_label: String = ""


func format_operation_status_view(status_view: Dictionary) -> String:
	if status_view.is_empty():
		return ""

	var status_key := str(status_view.get("status_key", "")).strip_edges()
	match status_key:
		"pending":
			var sec := maxi(0, int(status_view.get("remaining_sec", 0)))
			var fmt := pending_status_format.strip_edges()
			if fmt.is_empty():
				return ""
			return fmt % sec
		"ready":
			if allow_auto_complete:
				return ready_status_label.strip_edges()
			var awaiting := awaiting_confirmation_status_label.strip_edges()
			if not awaiting.is_empty():
				return awaiting
			return ready_status_label.strip_edges()
		"completed":
			return completed_status_label.strip_edges()
		"cancelled":
			return cancelled_status_label.strip_edges()
		_:
			return ""
