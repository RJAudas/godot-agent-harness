extends Node
class_name ScenegraphRuntime

signal capture_ready(snapshot, diagnostics)
signal persistence_completed(manifest)
signal runtime_error(message)

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphCaptureService = preload("res://addons/agent_runtime_harness/runtime/scenegraph_capture_service.gd")
const ScenegraphDiagnosticSerializer = preload("res://addons/agent_runtime_harness/runtime/scenegraph_diagnostic_serializer.gd")
const ScenegraphArtifactWriter = preload("res://addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd")

var _capture_service := ScenegraphCaptureService.new()
var _diagnostic_serializer := ScenegraphDiagnosticSerializer.new()
var _artifact_writer := ScenegraphArtifactWriter.new()

var _session_context := {}
var _expectations: Array = []
var _latest_snapshot := {}
var _latest_diagnostics: Array = []


func _ready() -> void:
	if _session_context.is_empty():
		configure_session({})
	call_deferred("_capture_startup_if_enabled")


func configure_session(session_context: Dictionary) -> void:
	_session_context = {
		"session_id": session_context.get("session_id", _build_identifier("session")),
		"run_id": session_context.get("run_id", _build_identifier("run")),
		"scenario_id": session_context.get("scenario_id", "pong-scenegraph-happy-path"),
		"requested_by": session_context.get("requested_by", "editor_plugin"),
		"output_directory": session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY),
		"artifact_root": session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT),
		"capture_policy": session_context.get("capture_policy", {
			"startup": true,
			"manual": true,
			"failure": true,
		}),
	}

	if session_context.has("config_path"):
		_load_session_config(String(session_context.get("config_path")))


func request_manual_capture() -> Dictionary:
	return capture_scenegraph(InspectionConstants.TRIGGER_MANUAL, "manual_request")


func request_failure_capture(reason: String) -> Dictionary:
	return capture_scenegraph(InspectionConstants.TRIGGER_FAILURE, reason)


func capture_scenegraph(trigger_type: String, reason: String) -> Dictionary:
	var root_node := _resolve_root_node()
	if root_node == null:
		var error_message := "No active runtime scene is available for capture."
		emit_signal("runtime_error", error_message)
		return {}

	_latest_snapshot = _capture_service.capture_snapshot(root_node, _session_context, trigger_type, reason)
	_latest_diagnostics = _diagnostic_serializer.build_diagnostics(_latest_snapshot, _expectations)

	if trigger_type == InspectionConstants.TRIGGER_FAILURE and _latest_diagnostics.is_empty():
		_latest_diagnostics.append(_diagnostic_serializer.build_capture_error(String(_latest_snapshot.get("snapshot_id", "snapshot")), reason))

	if not _latest_diagnostics.is_empty() and String(_latest_snapshot.get("capture_status", "")) == InspectionConstants.CAPTURE_STATUS_COMPLETE:
		_latest_snapshot["capture_status"] = InspectionConstants.CAPTURE_STATUS_PARTIAL

	emit_signal("capture_ready", _latest_snapshot, _latest_diagnostics)
	return _latest_snapshot


func persist_latest_bundle() -> Dictionary:
	if _latest_snapshot.is_empty():
		request_manual_capture()

	if _latest_snapshot.is_empty():
		return {}

	var result := _artifact_writer.persist_bundle(_latest_snapshot, _latest_diagnostics, _session_context)
	emit_signal("persistence_completed", result.get("manifest", {}))
	return result


func _capture_startup_if_enabled() -> void:
	var capture_policy: Dictionary = _session_context.get("capture_policy", {})
	if capture_policy.get("startup", false):
		capture_scenegraph(InspectionConstants.TRIGGER_STARTUP, "session_started")


func _resolve_root_node() -> Node:
	if get_tree() == null:
		return null
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root


func _load_session_config(config_path: String) -> void:
	if not FileAccess.file_exists(config_path):
		return

	var config_file := FileAccess.open(config_path, FileAccess.READ)
	var parsed := JSON.parse_string(config_file.get_as_text())
	config_file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_session_context["scenario_id"] = parsed.get("scenarioId", _session_context.get("scenario_id", "pong-scenegraph-happy-path"))
	_session_context["artifact_root"] = parsed.get("artifactRoot", _session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT))
	_session_context["output_directory"] = parsed.get("outputDirectory", _session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	_session_context["capture_policy"] = parsed.get("capturePolicy", _session_context.get("capture_policy", {}))

	_expectations.clear()
	for expectation_path_value in parsed.get("expectationFiles", []):
		var expectation_path := String(expectation_path_value)
		_expectations.append_array(_load_expectations(expectation_path))


func _load_expectations(expectation_path: String) -> Array:
	if not FileAccess.file_exists(expectation_path):
		return []

	var handle := FileAccess.open(expectation_path, FileAccess.READ)
	var parsed := JSON.parse_string(handle.get_as_text())
	handle.close()

	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed.get("expectations", [])
	return []


func _build_identifier(prefix: String) -> String:
	return "%s-%s" % [prefix, str(int(Time.get_unix_time_from_system()))]