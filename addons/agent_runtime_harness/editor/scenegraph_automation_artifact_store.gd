@tool
extends RefCounted
class_name ScenegraphAutomationArtifactStore

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")


func read_json(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null

	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return null

	var parsed := JSON.parse_string(handle.get_as_text())
	handle.close()
	return parsed


func ensure_automation_layout(config: Dictionary) -> void:
	var automation: Dictionary = config.get("automation", {})
	_ensure_directory(String(automation.get("requestsDirectory", "res://harness/automation/requests")))
	_ensure_directory(String(automation.get("resultsDirectory", "res://harness/automation/results")))


func read_request(config: Dictionary) -> Dictionary:
	var request_path := get_request_path(config)
	var parsed = read_json(request_path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func clear_request(config: Dictionary) -> void:
	var request_path := get_request_path(config)
	if FileAccess.file_exists(request_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))


func write_capability_result(config: Dictionary, payload: Dictionary) -> Dictionary:
	var result_path := get_capability_result_path(config)
	return _write_json_atomically(result_path, payload)


func write_lifecycle_status(config: Dictionary, payload: Dictionary) -> Dictionary:
	var result_path := get_lifecycle_status_path(config)
	return _write_json_atomically(result_path, payload)


func write_run_result(config: Dictionary, payload: Dictionary) -> Dictionary:
	var result_path := get_run_result_path(config)
	return _write_json_atomically(result_path, payload)


func get_request_path(config: Dictionary) -> String:
	var automation: Dictionary = config.get("automation", {})
	return String(automation.get("requestPath", "res://harness/automation/requests/run-request.json"))


func get_capability_result_path(config: Dictionary) -> String:
	var automation: Dictionary = config.get("automation", {})
	return String(automation.get("capabilityResultPath", "res://harness/automation/results/capability.json"))


func get_lifecycle_status_path(config: Dictionary) -> String:
	var automation: Dictionary = config.get("automation", {})
	return String(automation.get("lifecycleStatusPath", "res://harness/automation/results/lifecycle-status.json"))


func get_run_result_path(config: Dictionary) -> String:
	var automation: Dictionary = config.get("automation", {})
	return String(automation.get("runResultPath", "res://harness/automation/results/run-result.json"))


func load_harness_config(config_path: String) -> Dictionary:
	var parsed = read_json(config_path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func build_status_payload(request_id: String, run_id: String, status: String, details: String, extras := {}) -> Dictionary:
	var payload := {
		"requestId": request_id,
		"runId": run_id,
		"status": status,
		"details": details,
		"timestamp": InspectionConstants.utc_timestamp_now(),
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
	}
	for key in extras.keys():
		payload[key] = extras[key]
	return payload


func build_validation_result(manifest: Dictionary, missing_artifacts: Array, bundle_valid: bool, notes: Array) -> Dictionary:
	return {
		"manifestExists": not manifest.is_empty(),
		"artifactRefsChecked": int(manifest.get("artifactRefs", []).size()),
		"missingArtifacts": missing_artifacts.duplicate(true),
		"bundleValid": bundle_valid,
		"notes": notes.duplicate(true),
		"validatedAt": InspectionConstants.utc_timestamp_now(),
	}


func build_behavior_watch_failure_status_extras(validation_result: Dictionary) -> Dictionary:
	return {
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION,
		"evidenceRefs": build_behavior_watch_validation_refs(validation_result),
	}


func build_behavior_watch_validation_refs(validation_result: Dictionary) -> Array:
	var refs: Array = []
	for error_value in validation_result.get("errors", []):
		if typeof(error_value) != TYPE_DICTIONARY:
			continue
		refs.append(
			"behavior-watch:%s:%s" % [
				String(error_value.get("code", "invalid_request")),
				String(error_value.get("field", "behaviorWatchRequest")),
			]
		)
	return refs


func build_behavior_watch_validation_notes(validation_result: Dictionary) -> Array:
	var notes: Array = [
		"Behavior watch request was rejected before the playtest started.",
	]
	for error_value in validation_result.get("errors", []):
		if typeof(error_value) != TYPE_DICTIONARY:
			continue
		notes.append(String(error_value.get("message", "Behavior watch request validation failed.")))
	return notes


func build_build_diagnostic(resource_path, message: String, severity: String, line = null, column = null, source_kind: String = InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_UNKNOWN, code = null, raw_excerpt = null) -> Dictionary:
	return {
		"resourcePath": _normalize_optional_string(resource_path),
		"message": message,
		"severity": _normalize_build_severity(severity),
		"line": _normalize_optional_positive_int(line),
		"column": _normalize_optional_positive_int(column),
		"sourceKind": _normalize_build_source_kind(source_kind),
		"code": _normalize_optional_string(code),
		"rawExcerpt": _normalize_optional_string(raw_excerpt),
	}


func build_build_failure_payload(build_failure_phase: String, diagnostics: Array, raw_build_output: Array, details: String) -> Dictionary:
	return normalize_build_failure_payload({
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD,
		"buildFailurePhase": build_failure_phase,
		"buildDiagnostics": diagnostics,
		"rawBuildOutput": raw_build_output,
		"details": details,
	})


func build_build_failure_status_extras(build_failure_phase: String, diagnostics: Array, raw_build_output: Array) -> Dictionary:
	return {
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD,
		"buildFailurePhase": build_failure_phase,
		"buildDiagnosticCount": diagnostics.size(),
		"rawBuildOutputAvailable": not raw_build_output.is_empty(),
	}


func normalize_build_failure_payload(payload: Dictionary) -> Dictionary:
	var normalized_diagnostics: Array = []
	for diagnostic_value in payload.get("buildDiagnostics", []):
		if typeof(diagnostic_value) != TYPE_DICTIONARY:
			continue
		normalized_diagnostics.append(build_build_diagnostic(
			diagnostic_value.get("resourcePath", null),
			String(diagnostic_value.get("message", "")),
			String(diagnostic_value.get("severity", InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_UNKNOWN)),
			diagnostic_value.get("line", null),
			diagnostic_value.get("column", null),
			String(diagnostic_value.get("sourceKind", InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_UNKNOWN)),
			diagnostic_value.get("code", null),
			diagnostic_value.get("rawExcerpt", null)
		))

	var normalized_output: Array = []
	for output_value in payload.get("rawBuildOutput", []):
		var output_line := String(output_value)
		if output_line.is_empty():
			continue
		normalized_output.append(output_line)

	return {
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD,
		"buildFailurePhase": String(payload.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING)),
		"buildDiagnostics": normalized_diagnostics,
		"rawBuildOutput": normalized_output,
		"details": String(payload.get("details", "Build diagnostics were detected before runtime attachment.")),
	}


func _normalize_build_severity(severity: String) -> String:
	if severity in [
		InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
		InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_WARNING,
		InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_UNKNOWN,
	]:
		return severity
	return InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_UNKNOWN


func _normalize_build_source_kind(source_kind: String) -> String:
	if source_kind in [
		InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT,
		InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCENE,
		InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_RESOURCE,
		InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_UNKNOWN,
	]:
		return source_kind
	return InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_UNKNOWN


func _normalize_optional_positive_int(value):
	if value == null:
		return null
	var integer_value := int(value)
	if integer_value <= 0:
		return null
	return integer_value


func _normalize_optional_string(value):
	if value == null:
		return null
	var text := String(value)
	if text.is_empty():
		return null
	return text


func _write_json_atomically(path: String, payload: Variant) -> Dictionary:
	var parent_directory := path.get_base_dir()
	_ensure_directory(parent_directory)

	var temp_path := "%s.%s.tmp" % [path, str(Time.get_ticks_usec())]
	var write_error := _write_json(temp_path, payload)
	if not write_error.is_empty():
		return {
			"ok": false,
			"path": path,
			"error": write_error,
		}

	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_target := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_target)

	var rename_error := DirAccess.rename_absolute(absolute_temp, absolute_target)
	if rename_error != OK:
		DirAccess.remove_absolute(absolute_temp)
		return {
			"ok": false,
			"path": path,
			"error": "Could not move %s into place (%s)." % [path, error_string(rename_error)],
		}

	return {
		"ok": true,
		"path": path,
	}


func _write_json(path: String, payload: Variant) -> String:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return "Could not open %s for writing (%s)." % [path, error_string(FileAccess.get_open_error())]

	handle.store_string(JSON.stringify(payload, "\t"))
	handle.close()
	return ""


func _ensure_directory(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
