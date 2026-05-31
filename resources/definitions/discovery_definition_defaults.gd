## Shared discovery default normalization for celestial body / POI definitions.
class_name DiscoveryDefinitionDefaults
extends RefCounted

const DEFAULT_SIGNAL_DISPLAY_NAME := "Unknown Signal"
const DEFAULT_SIGNAL_TYPE_ID := "unknown"
const DEFAULT_SIGNAL_SHORT_LABEL := "Unknown"
const DEFAULT_SIGNAL_MARKER_LABEL := DiscoverySignalUiTextDefinition.FALLBACK_MARKER_LABEL


## Empty input = legacy (do not seed store; runtime getter falls back to KNOWN).
static func normalize_default_discovery_state(raw_state: String, context_label: String = "") -> String:
	var normalized := raw_state.strip_edges().to_lower()

	if normalized.is_empty():
		return ""

	match normalized:
		ObjectScanStore.DISCOVERY_HIDDEN, ObjectScanStore.DISCOVERY_SIGNAL, ObjectScanStore.DISCOVERY_KNOWN:
			return normalized
		_:
			var ctx := context_label.strip_edges()
			if ctx.is_empty():
				push_warning(
					"DiscoveryDefinitionDefaults: invalid default_discovery_state '%s', treating as legacy KNOWN."
					% raw_state
				)
			else:
				push_warning(
					(
						"DiscoveryDefinitionDefaults: invalid default_discovery_state '%s' on %s, "
						+ "treating as legacy KNOWN."
					)
					% [raw_state, ctx]
				)
			return ""
