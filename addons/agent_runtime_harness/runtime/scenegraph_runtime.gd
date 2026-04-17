extends Node
class_name ScenegraphRuntime

signal capture_ready(snapshot, diagnostics)
signal persistence_completed(manifest)
signal runtime_error(message)

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphCaptureService = preload("res://addons/agent_runtime_harness/runtime/scenegraph_capture_service.gd")
const ScenegraphDiagnosticSerializer = preload("res://addons/agent_runtime_harness/runtime/scenegraph_diagnostic_serializer.gd")
const ScenegraphArtifactWriter = preload("res://addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd")
const BehaviorWatchSampler = preload("res://addons/agent_runtime_harness/runtime/behavior_watch_sampler.gd")
const BehaviorTraceWriter = preload("res://addons/agent_runtime_harness/runtime/behavior_trace_writer.gd")

var _capture_service := ScenegraphCaptureService.new()
var _diagnostic_serializer := ScenegraphDiagnosticSerializer.new()
var _artifact_writer := ScenegraphArtifactWriter.new()
var _behavior_watch_sampler := BehaviorWatchSampler.new()
var _behavior_trace_writer := BehaviorTraceWriter.new()

var _session_context := {}
var _expectations: Array = []
var _latest_snapshot := {}
var _latest_diagnostics: Array = []
var _identifier_sequence := 0
var _applied_watch := {}
var _run_started_at_msec := 0


func _ready() -> void:
	set_physics_process(false)
	if _session_context.is_empty():
		configure_session({})
	_register_debugger_transport()
	call_deferred("_capture_startup_if_enabled")


func _exit_tree() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture(InspectionConstants.EDITOR_TO_RUNTIME_CHANNEL)


func configure_session(session_context: Dictionary) -> void:
	_run_started_at_msec = Time.get_ticks_msec()
	_session_context = {
		"session_id": session_context.get("session_id", _build_identifier("session")),
		"request_id": session_context.get("request_id", _build_identifier("request")),
		"run_id": session_context.get("run_id", _build_identifier("run")),
		"scenario_id": session_context.get("scenario_id", InspectionConstants.DEFAULT_SCENARIO_ID),
		"requested_by": session_context.get("requested_by", "editor_plugin"),
		"output_directory": session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY),
		"artifact_root": session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT),
		"capture_policy": session_context.get("capture_policy", {
			"startup": true,
			"manual": true,
			"failure": true,
		}),
		"stop_policy": session_context.get("stop_policy", {
			"stopAfterValidation": true,
		}),
	}
	_applied_watch = {}

	if session_context.has("applied_watch") and typeof(session_context.get("applied_watch")) == TYPE_DICTIONARY:
		_applied_watch = session_context.get("applied_watch", {}).duplicate(true)
	elif session_context.has("behavior_watch") and typeof(session_context.get("behavior_watch")) == TYPE_DICTIONARY:
		_applied_watch = session_context.get("behavior_watch", {}).get("appliedWatch", {}).duplicate(true)

	_behavior_watch_sampler.configure(_applied_watch)
	set_physics_process(_behavior_watch_sampler.is_enabled())

	if session_context.has("config_path"):
		_load_session_config(String(session_context.get("config_path")), session_context)

	_send_debugger_message("session_configured", [_build_session_configuration_event()])


func request_manual_capture() -> Dictionary:
	return capture_scenegraph(InspectionConstants.TRIGGER_MANUAL, "manual_request")


func request_failure_capture(reason: String) -> Dictionary:
	return capture_scenegraph(InspectionConstants.TRIGGER_FAILURE, reason)


func capture_scenegraph(trigger_type: String, reason: String) -> Dictionary:
	var root_node := _resolve_root_node()
	if root_node == null:
		_emit_runtime_error("No active runtime scene is available for capture.")
		return {}

	_latest_snapshot = _capture_service.capture_snapshot(root_node, _session_context, trigger_type, reason)
	_latest_diagnostics = _diagnostic_serializer.build_diagnostics(_latest_snapshot, _expectations)

	if trigger_type == InspectionConstants.TRIGGER_FAILURE and _latest_diagnostics.is_empty():
		_latest_diagnostics.append(_diagnostic_serializer.build_capture_error(String(_latest_snapshot.get("snapshot_id", "snapshot")), reason))

	if not _latest_diagnostics.is_empty() and String(_latest_snapshot.get("capture_status", "")) == InspectionConstants.CAPTURE_STATUS_COMPLETE:
		_latest_snapshot["capture_status"] = InspectionConstants.CAPTURE_STATUS_PARTIAL

	emit_signal("capture_ready", _latest_snapshot, _latest_diagnostics)
	_send_debugger_message("snapshot", [_latest_snapshot, _latest_diagnostics])
	return _latest_snapshot


func persist_latest_bundle() -> Dictionary:
	if _latest_snapshot.is_empty():
		request_manual_capture()

	if _latest_snapshot.is_empty():
		return {}

	var session_context := _session_context.duplicate(true)
	if not _applied_watch.is_empty():
		var trace_result := _behavior_trace_writer.persist_trace(_behavior_watch_sampler.get_rows(), session_context)
		if trace_result.has("error"):
			_emit_runtime_error(String(trace_result.get("error", "Behavior trace persistence failed.")))
			return trace_result

		var applied_watch := _applied_watch.duplicate(true)
		applied_watch["traceArtifact"] = String(trace_result.get("artifactPath", InspectionConstants.DEFAULT_BEHAVIOR_WATCH_TRACE_FILE)).get_file()
		applied_watch["outcomes"] = _behavior_watch_sampler.build_outcomes()
		session_context["behavior_watch"] = {
			"appliedWatch": applied_watch,
			"traceArtifactPath": trace_result.get("artifactPath", ""),
		}

	var result := _artifact_writer.persist_bundle(_latest_snapshot, _latest_diagnostics, session_context)
	if result.has("error"):
		_emit_runtime_error(String(result.get("error", "Scenegraph bundle persistence failed.")))
		return result

	emit_signal("persistence_completed", result.get("manifest", {}))
	_send_debugger_message("persisted", [result.get("manifest", {})])
	return result


func _capture_startup_if_enabled() -> void:
	var capture_policy: Dictionary = _session_context.get("capture_policy", {})
	if capture_policy.get("startup", false):
		capture_scenegraph(InspectionConstants.TRIGGER_STARTUP, "session_started")


func _physics_process(_delta: float) -> void:
	if not _behavior_watch_sampler.is_enabled():
		return
	_behavior_watch_sampler.capture_frame(self, Engine.get_process_frames(), _elapsed_run_time_msec())


func _resolve_root_node() -> Node:
	if get_tree() == null:
		return null
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root


func _load_session_config(config_path: String, caller_supplied: Dictionary = {}) -> void:
	if not FileAccess.file_exists(config_path):
		return

	var config_file := FileAccess.open(config_path, FileAccess.READ)
	var parsed := JSON.parse_string(config_file.get_as_text())
	config_file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		return

	if not caller_supplied.has("run_id"):
		_session_context["run_id"] = parsed.get("runId", _session_context.get("run_id", _build_identifier("run")))
	if not caller_supplied.has("scenario_id"):
		_session_context["scenario_id"] = parsed.get("scenarioId", _session_context.get("scenario_id", InspectionConstants.DEFAULT_SCENARIO_ID))
	if not caller_supplied.has("artifact_root"):
		_session_context["artifact_root"] = parsed.get("artifactRoot", _session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT))
	if not caller_supplied.has("output_directory"):
		_session_context["output_directory"] = parsed.get("outputDirectory", _session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	if not caller_supplied.has("capture_policy"):
		_session_context["capture_policy"] = parsed.get("capturePolicy", _session_context.get("capture_policy", {}))
	if not caller_supplied.has("stop_policy"):
		_session_context["stop_policy"] = parsed.get("defaultRequestOverrides", {}).get("stopPolicy", _session_context.get("stop_policy", {}))

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
	_identifier_sequence += 1
	return "%s-%s-%s" % [prefix, str(Time.get_ticks_usec()), str(_identifier_sequence)]


func _register_debugger_transport() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture(InspectionConstants.EDITOR_TO_RUNTIME_CHANNEL, _on_debugger_request)


func _on_debugger_request(message: String, data: Array) -> bool:
	match message:
		"configure_session":
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				configure_session(data[0])
			return true
		"request_manual_capture":
			request_manual_capture()
			return true
		"request_failure_capture":
			var reason := "failure_requested"
			if not data.is_empty():
				reason = String(data[0])
			request_failure_capture(reason)
			return true
		"persist_latest_bundle":
			persist_latest_bundle()
			return true
		_:
			return false


func _send_debugger_message(message_name: String, data: Array) -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message("%s:%s" % [InspectionConstants.RUNTIME_TO_EDITOR_CHANNEL, message_name], data)


func _build_session_configuration_event() -> Dictionary:
	var event := {
		"request_id": String(_session_context.get("request_id", "")),
		"session_id": String(_session_context.get("session_id", "")),
		"run_id": String(_session_context.get("run_id", "")),
		"scenario_id": String(_session_context.get("scenario_id", "")),
		"stop_policy": _session_context.get("stop_policy", {}).duplicate(true),
	}
	if not _applied_watch.is_empty():
		event["appliedWatch"] = _applied_watch.duplicate(true)
	return event


func _elapsed_run_time_msec() -> int:
	return max(Time.get_ticks_msec() - _run_started_at_msec, 0)


func _emit_runtime_error(message: String) -> void:
	emit_signal("runtime_error", message)
	_send_debugger_message("runtime_error", [message])
