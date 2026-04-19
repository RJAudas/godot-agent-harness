extends RefCounted
class_name InputDispatchRequestValidator

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")


func normalize_request(
	request_value: Variant,
	run_id: String,
	declared_actions: Array = [],
	capability: Dictionary = {}
) -> Dictionary:
	if typeof(request_value) != TYPE_DICTIONARY:
		return _build_rejection([
			_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_INVALID_REQUEST,
				"inputDispatchScript",
				"Input dispatch script must be an object."
			),
		])

	var capability_error := _check_capability(capability)
	if not capability_error.is_empty():
		return _build_rejection([capability_error])

	var request: Dictionary = (request_value as Dictionary).duplicate(true)
	var errors: Array = []
	_collect_unknown_keys(
		errors,
		request.keys(),
		InspectionConstants.INPUT_DISPATCH_SUPPORTED_REQUEST_KEYS,
		""
	)

	var events_value: Variant = request.get("events", null)
	if typeof(events_value) != TYPE_ARRAY or (events_value as Array).is_empty():
		errors.append(_build_error(
			InspectionConstants.INPUT_DISPATCH_REJECTION_MISSING_FIELD,
			"events",
			"Input dispatch script must include at least one event."
		))
		return _build_rejection(errors)

	var events_array: Array = events_value as Array
	if events_array.size() > InspectionConstants.INPUT_DISPATCH_MAX_EVENTS:
		errors.append(_build_error(
			InspectionConstants.INPUT_DISPATCH_REJECTION_SCRIPT_TOO_LONG,
			"events",
			"Input dispatch script must contain at most %d events." % InspectionConstants.INPUT_DISPATCH_MAX_EVENTS
		))
		return _build_rejection(errors)

	var declared_action_set := _build_action_set(declared_actions)
	var normalized_events: Array = []
	var seen_event_keys := {}
	var press_state := {}

	for index in range(events_array.size()):
		var event_value: Variant = events_array[index]
		var field_prefix := "events[%d]" % index
		if typeof(event_value) != TYPE_DICTIONARY:
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_INVALID_REQUEST,
				field_prefix,
				"Each input dispatch event must be an object."
			))
			continue

		var event: Dictionary = event_value as Dictionary
		_collect_unknown_keys(
			errors,
			event.keys(),
			InspectionConstants.INPUT_DISPATCH_SUPPORTED_EVENT_KEYS,
			field_prefix + "."
		)

		var has_field_error := false

		if not event.has("kind"):
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_MISSING_FIELD,
				field_prefix + ".kind",
				"Input dispatch event must declare a kind."
			))
			has_field_error = true
		if not event.has("identifier"):
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_MISSING_FIELD,
				field_prefix + ".identifier",
				"Input dispatch event must declare an identifier."
			))
			has_field_error = true
		if not event.has("phase"):
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_MISSING_FIELD,
				field_prefix + ".phase",
				"Input dispatch event must declare a phase."
			))
			has_field_error = true
		if not event.has("frame"):
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_MISSING_FIELD,
				field_prefix + ".frame",
				"Input dispatch event must declare a frame."
			))
			has_field_error = true

		if has_field_error:
			continue

		var kind := String(event.get("kind", "")).strip_edges()
		if not kind in InspectionConstants.INPUT_DISPATCH_SUPPORTED_KINDS:
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_FIELD,
				field_prefix + ".kind",
				"Input dispatch event kind '%s' is not supported. Use 'key' or 'action'." % kind
			))
			continue

		var phase := String(event.get("phase", "")).strip_edges()
		if not phase in InspectionConstants.INPUT_DISPATCH_SUPPORTED_PHASES:
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_INVALID_PHASE,
				field_prefix + ".phase",
				"Input dispatch phase must be 'press' or 'release'."
			))
			continue

		var frame_value: Variant = event.get("frame")
		if not _is_integral_numeric(frame_value):
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_INVALID_FRAME,
				field_prefix + ".frame",
				"Input dispatch frame must be a non-negative integer."
			))
			continue
		var frame := int(frame_value)
		if frame < 0:
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_INVALID_FRAME,
				field_prefix + ".frame",
				"Input dispatch frame must be a non-negative integer."
			))
			continue

		var order_value: Variant = event.get("order", index)
		var order := index
		if event.has("order"):
			if not _is_integral_numeric(order_value) or int(order_value) < 0:
				errors.append(_build_error(
					InspectionConstants.INPUT_DISPATCH_REJECTION_INVALID_FRAME,
					field_prefix + ".order",
					"Input dispatch order must be a non-negative integer."
				))
				continue
			order = int(order_value)

		var identifier := String(event.get("identifier", "")).strip_edges()
		if identifier.is_empty():
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_IDENTIFIER,
				field_prefix + ".identifier",
				"Input dispatch identifier must be a non-empty string."
			))
			continue

		if kind == "key":
			if not _is_supported_key_identifier(identifier):
				errors.append(_build_error(
					InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_IDENTIFIER,
					field_prefix + ".identifier",
					"Input dispatch key identifier '%s' is not a supported logical Key enum name." % identifier
				))
				continue
		elif kind == "action":
			if not declared_action_set.is_empty() and not declared_action_set.has(identifier):
				errors.append(_build_error(
					InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_IDENTIFIER,
					field_prefix + ".identifier",
					"Input dispatch action '%s' is not declared in the project InputMap." % identifier
				))
				continue

		var dedup_key := "%s|%s|%s|%d|%d" % [kind, identifier, phase, frame, order]
		if seen_event_keys.has(dedup_key):
			errors.append(_build_error(
				InspectionConstants.INPUT_DISPATCH_REJECTION_DUPLICATE_EVENT,
				field_prefix,
				"Input dispatch event duplicates an earlier declaration."
			))
			continue
		seen_event_keys[dedup_key] = true

		var press_key := "%s|%s" % [kind, identifier]
		if phase == "press":
			press_state[press_key] = int(press_state.get(press_key, 0)) + 1
		else:
			var outstanding := int(press_state.get(press_key, 0))
			if outstanding <= 0:
				errors.append(_build_error(
					InspectionConstants.INPUT_DISPATCH_REJECTION_UNMATCHED_RELEASE,
					field_prefix,
					"Input dispatch release event '%s' has no matching prior press." % identifier
				))
				continue
			press_state[press_key] = outstanding - 1

		normalized_events.append({
			"kind": kind,
			"identifier": identifier,
			"phase": phase,
			"frame": frame,
			"order": order,
			"declaredIndex": index,
		})

	if not errors.is_empty():
		return _build_rejection(errors)

	normalized_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("frame", 0)) != int(b.get("frame", 0)):
			return int(a.get("frame", 0)) < int(b.get("frame", 0))
		if int(a.get("order", 0)) != int(b.get("order", 0)):
			return int(a.get("order", 0)) < int(b.get("order", 0))
		return int(a.get("declaredIndex", 0)) < int(b.get("declaredIndex", 0))
	)

	var normalized_request := {
		"events": normalized_events.duplicate(true),
	}
	var applied_dispatch := {
		"runId": run_id,
		"events": normalized_events.duplicate(true),
		"eventCount": normalized_events.size(),
		"outcomeArtifact": InspectionConstants.DEFAULT_INPUT_DISPATCH_OUTCOMES_FILE,
		"rejectedFields": [],
	}
	return {
		"accepted": true,
		"request": normalized_request,
		"appliedDispatch": applied_dispatch,
		"errors": [],
		"rejectedFields": [],
	}


func _check_capability(capability: Dictionary) -> Dictionary:
	if capability.is_empty():
		return {}
	if not capability.has("supported"):
		return {}
	if bool(capability.get("supported", true)):
		return {}
	var reason := String(capability.get("reason", "capability_unsupported")).strip_edges()
	if reason.is_empty():
		reason = "capability_unsupported"
	return _build_error(
		InspectionConstants.INPUT_DISPATCH_REJECTION_CAPABILITY_UNSUPPORTED,
		"inputDispatchScript",
		"Input dispatch is not supported on the current editor: %s" % reason
	)


func _collect_unknown_keys(
	errors: Array,
	keys: Array,
	supported_keys: Array,
	field_prefix: String
) -> void:
	for key_value in keys:
		var key := String(key_value)
		if key in supported_keys:
			continue
		var code := InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_FIELD
		if key in InspectionConstants.INPUT_DISPATCH_LATER_SLICE_FIELDS:
			code = InspectionConstants.INPUT_DISPATCH_REJECTION_LATER_SLICE_FIELD
		errors.append(_build_error(
			code,
			"%s%s" % [field_prefix, key],
			"Input dispatch field '%s' is not supported in slice 1." % key
		))


func _build_action_set(declared_actions: Array) -> Dictionary:
	var action_set := {}
	for action_value in declared_actions:
		var action_name := String(action_value).strip_edges()
		if not action_name.is_empty():
			action_set[action_name] = true
	return action_set


func _is_supported_key_identifier(identifier: String) -> bool:
	if identifier.is_empty():
		return false
	for character in identifier:
		var ascii := character.unicode_at(0)
		var is_upper := ascii >= 65 and ascii <= 90
		var is_digit := ascii >= 48 and ascii <= 57
		var is_underscore := ascii == 95
		if not (is_upper or is_digit or is_underscore):
			return false
	var key_value: Variant = ClassDB.class_get_integer_constant("@GlobalScope", "KEY_%s" % identifier)
	return typeof(key_value) == TYPE_INT and int(key_value) != 0


func _is_integral_numeric(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_equal_approx(float(value), round(float(value)))


func _build_rejection(errors: Array) -> Dictionary:
	var rejected_fields: Array = []
	for error_value in errors:
		if typeof(error_value) != TYPE_DICTIONARY:
			continue
		var field_name := String((error_value as Dictionary).get("field", "")).strip_edges()
		if field_name.is_empty() or field_name in rejected_fields:
			continue
		rejected_fields.append(field_name)
	return {
		"accepted": false,
		"request": {},
		"appliedDispatch": {},
		"errors": errors.duplicate(true),
		"rejectedFields": rejected_fields,
	}


func _build_error(code: String, field: String, message: String) -> Dictionary:
	return {
		"code": code,
		"field": field,
		"message": message,
	}
