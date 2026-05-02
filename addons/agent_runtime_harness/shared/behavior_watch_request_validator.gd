extends RefCounted
class_name BehaviorWatchRequestValidator

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")

const SUPPORTED_TARGET_KEYS := ["nodePath", "properties"]
const SUPPORTED_CADENCE_KEYS := ["mode", "everyNFrames"]
const SUPPORTED_REQUEST_KEYS := ["targets", "cadence", "startFrameOffset", "frameCount"]
const SUPPORTED_PROPERTIES := [
	"position",
	"velocity",
	"intendedVelocity",
	"collisionState",
	"lastCollider",
	"movementVector",
	"speed",
	"overlapFrames",
	"text",
	"linear_velocity",
	"angular_velocity",
	"modulate",
	"visible",
	"rotation",
	"scale",
]
const LATER_SLICE_KEYS := [
	"triggers",
	"invariants",
	"scriptProbes",
	"probeScripts",
	"fullSceneCapture",
	"fullSceneLogging",
]


func normalize_request(request_value: Variant, run_id: String) -> Dictionary:
	if typeof(request_value) != TYPE_DICTIONARY:
		return _build_rejection([
			_build_error("invalid_request", "behaviorWatchRequest", "Behavior watch request must be an object."),
		])

	var request: Dictionary = request_value.duplicate(true)
	var errors: Array = []
	_collect_unknown_keys(errors, request.keys(), SUPPORTED_REQUEST_KEYS, "")

	var normalized_targets := _normalize_targets(request.get("targets", []), errors)
	var normalized_cadence := _normalize_cadence(request.get("cadence", null), errors)
	var start_frame_offset := _normalize_non_negative_int(
		request.get("startFrameOffset", 0),
		"startFrameOffset",
		"invalid_start_frame_offset",
		"Behavior watch startFrameOffset must be a non-negative integer.",
		errors
	)
	var frame_count := _normalize_positive_int(
		request.get("frameCount", null),
		"frameCount",
		"zero_sample_window",
		"Behavior watch frameCount must be a positive integer.",
		errors
	)

	if not errors.is_empty():
		return _build_rejection(errors)

	var normalized_request := {
		"targets": normalized_targets,
		"cadence": normalized_cadence,
		"startFrameOffset": start_frame_offset,
		"frameCount": frame_count,
	}
	var applied_watch := {
		"runId": run_id,
		"targets": normalized_targets.duplicate(true),
		"cadence": normalized_cadence.duplicate(true),
		"startFrameOffset": start_frame_offset,
		"frameCount": frame_count,
		"traceArtifact": InspectionConstants.DEFAULT_BEHAVIOR_WATCH_TRACE_FILE,
	}
	return {
		"accepted": true,
		"request": normalized_request,
		"appliedWatch": applied_watch,
		"errors": [],
		"rejectedFields": [],
	}


func _normalize_targets(targets_value: Variant, errors: Array) -> Array:
	var normalized_targets: Array = []
	if typeof(targets_value) != TYPE_ARRAY or targets_value.is_empty():
		errors.append(_build_error("missing_targets", "targets", "Behavior watch request must include at least one target."))
		return normalized_targets

	for index in range(targets_value.size()):
		var target_value = targets_value[index]
		if typeof(target_value) != TYPE_DICTIONARY:
			errors.append(_build_error("invalid_target", "targets[%d]" % index, "Each behavior watch target must be an object."))
			continue

		var target: Dictionary = target_value
		_collect_unknown_keys(errors, target.keys(), SUPPORTED_TARGET_KEYS, "targets[%d]." % index)

		var node_path := String(target.get("nodePath", "")).strip_edges()
		if node_path.is_empty() or not node_path.begins_with("/root/"):
			errors.append(_build_error(
				"unsupported_selector",
				"targets[%d].nodePath" % index,
				"Behavior watch targets must use absolute runtime node paths under /root/."
			))

		var normalized_properties: Array = []
		var seen_properties := {}
		var properties_value = target.get("properties", [])
		if typeof(properties_value) != TYPE_ARRAY or properties_value.is_empty():
			errors.append(_build_error(
				"missing_properties",
				"targets[%d].properties" % index,
				"Behavior watch targets must list at least one supported property."
			))
		else:
			for property_value in properties_value:
				var property_name := String(property_value).strip_edges()
				if property_name.is_empty():
					errors.append(_build_error(
						"unsupported_property",
						"targets[%d].properties" % index,
						"Behavior watch target properties must be non-empty strings."
					))
					continue
				if not property_name in SUPPORTED_PROPERTIES:
					errors.append(_build_error(
						"unsupported_property",
						"targets[%d].properties" % index,
						"Behavior watch property '%s' is not in the supported allowlist. Allowed values: %s." % [property_name, ", ".join(SUPPORTED_PROPERTIES)]
					))
					continue
				if seen_properties.has(property_name):
					continue
				seen_properties[property_name] = true
				normalized_properties.append(property_name)

		if node_path.is_empty() or normalized_properties.is_empty():
			continue

		normalized_targets.append({
			"nodePath": node_path,
			"properties": normalized_properties,
		})

	if normalized_targets.is_empty() and errors.is_empty():
		errors.append(_build_error("missing_targets", "targets", "Behavior watch request did not resolve any valid targets."))
	return normalized_targets


func _normalize_cadence(cadence_value: Variant, errors: Array) -> Dictionary:
	if cadence_value == null:
		return {
			"mode": "every_frame",
			"everyNFrames": null,
		}

	if typeof(cadence_value) != TYPE_DICTIONARY:
		errors.append(_build_error("invalid_cadence", "cadence", "Behavior watch cadence must be an object."))
		return {
			"mode": "every_frame",
			"everyNFrames": null,
		}

	var cadence: Dictionary = cadence_value
	_collect_unknown_keys(errors, cadence.keys(), SUPPORTED_CADENCE_KEYS, "cadence.")

	var mode := String(cadence.get("mode", "every_frame")).strip_edges()
	if mode.is_empty():
		mode = "every_frame"

	if mode == "every_frame":
		if cadence.has("everyNFrames") and cadence.get("everyNFrames") != null:
			errors.append(_build_error(
				"invalid_cadence",
				"cadence.everyNFrames",
				"Behavior watch cadence everyNFrames is only supported when mode is every_n_frames."
			))
		return {
			"mode": mode,
			"everyNFrames": null,
		}

	if mode != "every_n_frames":
		errors.append(_build_error(
			"invalid_cadence",
			"cadence.mode",
			"Behavior watch cadence mode must be every_frame or every_n_frames."
		))
		return {
			"mode": "every_frame",
			"everyNFrames": null,
		}

	var every_n_frames := _normalize_positive_int(
		cadence.get("everyNFrames", null),
		"cadence.everyNFrames",
		"invalid_cadence",
		"Behavior watch cadence everyNFrames must be an integer greater than or equal to 2.",
		errors,
		2
	)
	return {
		"mode": mode,
		"everyNFrames": every_n_frames if every_n_frames > 0 else 2,
	}


func _normalize_non_negative_int(
	value: Variant,
	field: String,
	code: String,
	message: String,
	errors: Array
) -> int:
	if value == null:
		return 0
	if not _is_integral_numeric(value):
		errors.append(_build_error(code, field, message))
		return 0
	var normalized_value := int(value)
	if normalized_value < 0:
		errors.append(_build_error(code, field, message))
		return 0
	return normalized_value


func _normalize_positive_int(
	value: Variant,
	field: String,
	code: String,
	message: String,
	errors: Array,
	minimum := 1
) -> int:
	if value == null or not _is_integral_numeric(value):
		errors.append(_build_error(code, field, message))
		return 0
	var normalized_value := int(value)
	if normalized_value < minimum:
		errors.append(_build_error(code, field, message))
		return 0
	return normalized_value


func _is_integral_numeric(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_equal_approx(float(value), round(float(value)))


func _collect_unknown_keys(errors: Array, keys: Array, supported_keys: Array, field_prefix: String) -> void:
	for key_value in keys:
		var key := String(key_value)
		if key in supported_keys:
			continue
		var code := "unsupported_field"
		if key in LATER_SLICE_KEYS:
			code = "later_slice_field"
		errors.append(_build_error(
			code,
			"%s%s" % [field_prefix, key],
			"Behavior watch field '%s' is not supported in slice 1 or slice 2." % key
		))


func _build_rejection(errors: Array) -> Dictionary:
	var rejected_fields: Array = []
	for error_value in errors:
		if typeof(error_value) != TYPE_DICTIONARY:
			continue
		var field_name := String(error_value.get("field", "")).strip_edges()
		if field_name.is_empty() or field_name in rejected_fields:
			continue
		rejected_fields.append(field_name)
	return {
		"accepted": false,
		"request": {},
		"appliedWatch": {},
		"errors": errors.duplicate(true),
		"rejectedFields": rejected_fields,
	}


func _build_error(code: String, field: String, message: String) -> Dictionary:
	return {
		"code": code,
		"field": field,
		"message": message,
	}
