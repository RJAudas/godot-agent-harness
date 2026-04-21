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
const InputDispatchRuntime = preload("res://addons/agent_runtime_harness/runtime/input_dispatch_runtime.gd")

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
var _input_dispatch_runtime: InputDispatchRuntime = null

## Per-run dedup map for runtime error and warning records.
## Key: "<scriptPath>|<line>|<severity>" (String)
## Value: Dictionary matching the runtime-error-record schema.
var _runtime_error_dedup: Dictionary = {}
## Monotonically increasing ordinal per dedup-key first occurrence.
var _runtime_error_ordinal := 0
## Pause-on-error state (US2/T021-T022). Set to false in degraded mode.
var _pause_on_error_enabled := true
## -1 = no outstanding pause; >= 0 = current pauseId.
var _pending_pause_id := -1
## Monotonic counter for generating unique pauseIds in this run.
var _pause_counter := 0
## Fix #17: ensures the startup capture fires at most once per game launch.
var _startup_capture_fired := false
## Fix #17: reference to the session-ready watchdog timer.
var _session_ready_watchdog: SceneTreeTimer = null


func _ready() -> void:
	set_physics_process(false)
	if _session_context.is_empty():
		configure_session({})
	_register_debugger_transport()
	# Fix #17: Gate startup capture behind editor handshake instead of firing
	# immediately via call_deferred, which races the broker's configure_session.
	_notify_editor_session_ready()


func _exit_tree() -> void:
	# Fix #17: prevent the watchdog from firing into a dead tree after teardown.
	_startup_capture_fired = true
	_cancel_session_ready_watchdog()
	_flush_pending_input_dispatch_outcomes()
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture(InspectionConstants.EDITOR_TO_RUNTIME_CHANNEL)


func configure_session(session_context: Dictionary) -> void:
	_run_started_at_msec = Time.get_ticks_msec()
	_runtime_error_dedup.clear()
	_runtime_error_ordinal = 0
	# T034: default to enabled; degraded mode disables pause-on-error if capability says unavailable.
	_pause_on_error_enabled = String(session_context.get("pause_on_error_mode", InspectionConstants.PAUSE_ON_ERROR_MODE_ACTIVE)) == InspectionConstants.PAUSE_ON_ERROR_MODE_ACTIVE
	_pending_pause_id = -1
	_pause_counter = 0
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

	if session_context.has(InspectionConstants.INPUT_DISPATCH_RUNTIME_KEY_APPLIED):
		_session_context[InspectionConstants.INPUT_DISPATCH_RUNTIME_KEY_APPLIED] = session_context.get(InspectionConstants.INPUT_DISPATCH_RUNTIME_KEY_APPLIED, {}).duplicate(true)
	if session_context.has("applied_input_dispatch"):
		_session_context["applied_input_dispatch"] = session_context.get("applied_input_dispatch", {}).duplicate(true)

	if session_context.has("config_path"):
		_load_session_config(String(session_context.get("config_path")), session_context)

	_send_debugger_message("session_configured", [_build_session_configuration_event()])
	_install_input_dispatch_runtime_if_needed()


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

	# Attach runtime error records for T016 (artifact writer flush).
	if not _runtime_error_dedup.is_empty():
		session_context["runtime_error_records"] = get_runtime_error_records()

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


## Fix #17: After registering the transport, announce readiness to the editor so it
## can send configure_session before the startup capture fires.  Falls back to
## an immediate (deferred) trigger when running without an editor debugger.
func _notify_editor_session_ready() -> void:
	if not EngineDebugger.is_active():
		# Standalone game: no editor handshake is possible; trigger startup
		# capture after the autoload's own configure_session call completes.
		call_deferred("_trigger_startup_capture_if_pending")
		return
	_send_debugger_message(InspectionConstants.RUNTIME_TO_EDITOR_MSG_SESSION_READY, [_session_context.duplicate(true)])
	_start_session_ready_watchdog()


## Fix #17: Arm a watchdog so a missing or delayed editor reply never prevents
## the startup capture from firing.
func _start_session_ready_watchdog() -> void:
	if get_tree() == null:
		return
	_session_ready_watchdog = get_tree().create_timer(
		InspectionConstants.SESSION_READY_WATCHDOG_MSEC / 1000.0, false)
	_session_ready_watchdog.timeout.connect(_on_session_ready_watchdog_timeout)


func _on_session_ready_watchdog_timeout() -> void:
	_session_ready_watchdog = null
	_trigger_startup_capture_if_pending()


func _cancel_session_ready_watchdog() -> void:
	if _session_ready_watchdog != null:
		if _session_ready_watchdog.timeout.is_connected(_on_session_ready_watchdog_timeout):
			_session_ready_watchdog.timeout.disconnect(_on_session_ready_watchdog_timeout)
		_session_ready_watchdog = null


## Fix #17: Idempotent gate — fires the startup capture exactly once per launch.
func _trigger_startup_capture_if_pending() -> void:
	if _startup_capture_fired:
		return
	_startup_capture_fired = true
	_cancel_session_ready_watchdog()
	_capture_startup_if_enabled()


func _register_debugger_transport() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture(InspectionConstants.EDITOR_TO_RUNTIME_CHANNEL, _on_debugger_request)


func _on_debugger_request(message: String, data: Array) -> bool:
	match message:
		"configure_session":
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				configure_session(data[0])
				# Fix #17: trigger startup capture now that broker context is applied.
				_trigger_startup_capture_if_pending()
			return true
		InspectionConstants.EDITOR_TO_RUNTIME_MSG_CONFIGURE_SESSION_SKIP:
			# Fix #17: editor has no broker context; proceed with file-loaded context.
			_trigger_startup_capture_if_pending()
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
		InspectionConstants.RUNTIME_ERROR_MSG_RECORD:
			# The editor bridge forwards structured error records (intercepted from
			# the engine's built-in error channel) back to the runtime so the dedup
			# map is maintained here alongside the existing session context.
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				_record_runtime_error_from_editor(data[0])
			return true
		InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION:
			# The editor/broker has resolved an outstanding pause decision.
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				_handle_pause_decision(data[0])
			return true
		InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION_LOG:
			# The editor sends the completed pause decision log just before
			# persisting, so the artifact writer can flush it to JSONL.
			if not data.is_empty() and typeof(data[0]) == TYPE_ARRAY:
				_session_context["pause_decision_log"] = data[0]
			return true
		InspectionConstants.RUNTIME_ERROR_MSG_SET_TERMINATION:
			# T031: The coordinator sends the derived runtime termination before
			# requesting persist_latest_bundle, so the artifact writer stamps it.
			if not data.is_empty() and typeof(data[0]) == TYPE_STRING:
				_session_context["termination"] = String(data[0])
			return true
		"breakpoint":
			# T022: The engine informs the runtime of a user breakpoint pause.
			# We do NOT increment a dedup counter for breakpoints.
			if _pending_pause_id < 0:
				var bp_file := String(data[0]) if data.size() > 0 else "unknown"
				var bp_line := int(data[1]) if data.size() > 1 else -1
				var bp_record := {
					"scriptPath": bp_file if not bp_file.is_empty() else "unknown",
					"line": bp_line if bp_line > 0 else null,
					"function": null,
					"message": "Execution paused at user breakpoint.",
				}
				_raise_runtime_pause(bp_record, InspectionConstants.PAUSE_CAUSE_USER_BREAKPOINT)
			return true
		_:
			return false


## Record a structured runtime error dict forwarded from the editor bridge.
## Maintains the per-run dedup map keyed by (scriptPath, line, severity).
func _record_runtime_error_from_editor(record: Dictionary) -> void:
	var script_path := String(record.get("scriptPath", "unknown"))
	var line: int = int(record.get("line", -1))
	var severity := String(record.get("severity", InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR))
	var dedup_key := "%s|%d|%s" % [script_path, line, severity]

	var now_ts := InspectionConstants.utc_timestamp_now()
	if _runtime_error_dedup.has(dedup_key):
		var existing: Dictionary = _runtime_error_dedup[dedup_key]
		var count: int = int(existing.get("repeatCount", 1))
		if count < InspectionConstants.RUNTIME_ERROR_REPEAT_CAP:
			existing["repeatCount"] = count + 1
			existing["lastSeenAt"] = now_ts
		else:
			# Cap reached; annotate once.
			existing["truncatedAt"] = InspectionConstants.RUNTIME_ERROR_REPEAT_CAP
	else:
		_runtime_error_ordinal += 1
		var new_record := {
			"runId": String(_session_context.get("run_id", "")),
			"ordinal": _runtime_error_ordinal,
			"scriptPath": script_path,
			"line": line if line > 0 else null,
			"function": String(record.get("function", "")),
			"message": String(record.get("message", "")),
			"severity": severity,
			"firstSeenAt": now_ts,
			"lastSeenAt": now_ts,
			"repeatCount": 1,
		}
		_runtime_error_dedup[dedup_key] = new_record
		# Send the first-occurrence record onward to the editor for real-time
		# awareness (e.g. the run coordinator can update its anchor tracker).
		_send_debugger_message(InspectionConstants.RUNTIME_ERROR_MSG_RECORD, [new_record])

		# T030: Flush the last-error anchor sidecar so a sudden crash leaves a
		# recoverable on-disk anchor for the coordinator to read.
		if severity == InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR:
			_flush_last_error_anchor(new_record)

		# US2/T021: raise a debug pause on first occurrence of an error-severity record.
		if severity == InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR and _pause_on_error_enabled and _pending_pause_id < 0:
			_raise_runtime_pause(new_record, InspectionConstants.PAUSE_CAUSE_RUNTIME_ERROR)


## Return a copy of the current dedup map as an array of record dicts,
## sorted by firstSeenAt (ascending), then ordinal.
func get_runtime_error_records() -> Array:
	var records: Array = _runtime_error_dedup.values().duplicate(true)
	records.sort_custom(func(a, b):
		var ta := String(a.get("firstSeenAt", ""))
		var tb := String(b.get("firstSeenAt", ""))
		if ta != tb:
			return ta < tb
		return int(a.get("ordinal", 0)) < int(b.get("ordinal", 0))
	)
	return records


func _send_debugger_message(message_name: String, data: Array) -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message("%s:%s" % [InspectionConstants.RUNTIME_TO_EDITOR_CHANNEL, message_name], data)


## T030: Write (or overwrite) the last-error-anchor.json sidecar inside the run's
## output directory so a sudden process exit leaves a recoverable anchor on disk.
func _flush_last_error_anchor(error_record: Dictionary) -> void:
	var output_dir := String(_session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	# ProjectSettings.globalize_path converts "res://" to an absolute OS path.
	var abs_dir := ProjectSettings.globalize_path(output_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var sidecar_path := abs_dir.path_join(InspectionConstants.DEFAULT_LAST_ERROR_ANCHOR_FILE)
	var anchor := {
		"scriptPath": String(error_record.get("scriptPath", "unknown")),
		"line": error_record.get("line"),
		"severity": String(error_record.get("severity", InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR)),
		"message": String(error_record.get("message", "")),
	}
	var handle := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if handle != null:
		handle.store_string(JSON.stringify(anchor))
		handle.close()


## US2/T021: Raise the engine's debug-pause state and emit a runtime_pause message.
func _raise_runtime_pause(error_record: Dictionary, cause: String) -> void:
	_pause_counter += 1
	_pending_pause_id = _pause_counter - 1   # 0-based
	var pause_msg := {
		"pauseId": _pending_pause_id,
		"runId": String(_session_context.get("run_id", "")),
		"cause": cause,
		"scriptPath": String(error_record.get("scriptPath", "unknown")),
		"line": error_record.get("line"),
		"function": error_record.get("function"),
		"message": String(error_record.get("message", "")),
		"processFrame": Engine.get_process_frames(),
		"raisedAt": InspectionConstants.utc_timestamp_now(),
	}
	_send_debugger_message(InspectionConstants.RUNTIME_ERROR_MSG_PAUSE, [pause_msg])
	# Request the engine to pause execution so the agent has time to decide.
	EngineDebugger.debug(false, true)


## US2/T021: Handle a pause decision sent from the editor/broker.
func _handle_pause_decision(decision_data: Dictionary) -> void:
	var pause_id: int = int(decision_data.get("pauseId", -1))
	if pause_id != _pending_pause_id:
		# Reject stale or unknown pause decisions.
		var ack := {
			"pauseId": pause_id,
			"accepted": false,
			"reason": InspectionConstants.PAUSE_DECISION_REJECTION_UNKNOWN_PAUSE,
		}
		_send_debugger_message(InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION_ACK, [ack])
		return

	var decision := String(decision_data.get("decision", ""))
	_pending_pause_id = -1

	var ack := {
		"pauseId": pause_id,
		"accepted": true,
		"decision": decision,
	}
	_send_debugger_message(InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION_ACK, [ack])


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
	var applied_input_dispatch: Dictionary = _session_context.get("applied_input_dispatch", {})
	if not applied_input_dispatch.is_empty():
		event["appliedInputDispatch"] = applied_input_dispatch.duplicate(true)
	return event


func _elapsed_run_time_msec() -> int:
	return max(Time.get_ticks_msec() - _run_started_at_msec, 0)


func _emit_runtime_error(message: String) -> void:
	emit_signal("runtime_error", message)
	_send_debugger_message("runtime_error", [message])


func _install_input_dispatch_runtime_if_needed() -> void:
	var script_dict: Dictionary = _session_context.get(InspectionConstants.INPUT_DISPATCH_RUNTIME_KEY_APPLIED, {})
	if script_dict.is_empty():
		if _input_dispatch_runtime != null:
			_input_dispatch_runtime.configure({}, String(_session_context.get("run_id", "")))
		return

	var reset_error := String(_artifact_writer.reset_input_dispatch_outcomes(_session_context))
	if not reset_error.is_empty():
		_emit_runtime_error(reset_error)
		return

	if _input_dispatch_runtime == null:
		_input_dispatch_runtime = InputDispatchRuntime.new()
		_input_dispatch_runtime.name = "InputDispatchRuntime"
		_input_dispatch_runtime.outcome_recorded.connect(_on_input_dispatch_outcome)
		add_child(_input_dispatch_runtime)
	var run_id := String(_session_context.get("run_id", ""))
	_input_dispatch_runtime.configure(script_dict, run_id)


func _flush_pending_input_dispatch_outcomes() -> void:
	if _input_dispatch_runtime == null:
		return
	_input_dispatch_runtime.dispatch_remaining_as_skipped("")


func _on_input_dispatch_outcome(outcome: Dictionary) -> void:
	var append_error := String(_artifact_writer.append_input_dispatch_outcome(_session_context, outcome))
	if not append_error.is_empty():
		_emit_runtime_error("Failed to append input dispatch outcome evidence: %s" % append_error)
		return
	_send_debugger_message("input_dispatch_outcome", [outcome])
