@tool
extends RefCounted
class_name ScenegraphRunCoordinator

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphAutomationArtifactStore = preload("res://addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd")
const BehaviorWatchRequestValidator = preload("res://addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd")
const InputDispatchRequestValidator = preload("res://addons/agent_runtime_harness/shared/input_dispatch_request_validator.gd")

signal lifecycle_status_written(payload)
signal run_completed(result)

var _plugin: EditorPlugin
var _bridge
var _artifact_store: ScenegraphAutomationArtifactStore
var _active_config := {}
var _active_request := {}
var _active_capability := {}
var _last_manifest := {}
var _last_validation := {}
var _last_build_failure := {}
var _pending_failure_kind: Variant = null
var _pending_failure_message := ""
var _active := false
var _awaiting_runtime := false
var _awaiting_capture := false
var _awaiting_manifest := false
var _awaiting_stop := false
var _stop_requested := false
var _launch_started_at_usec := 0
var _active_config_path := ""
var _watch_request_validator := BehaviorWatchRequestValidator.new()
var _input_dispatch_validator := InputDispatchRequestValidator.new()
## Tracks the last runtime error anchor for crash classification (US3/T030).
var _last_error_anchor := {}
var _runtime_error_record_count := 0
## Fix #19: Coordinator-side dedup map for emergency persist on crash.
## Key: "<scriptPath>|<line>|<severity>".  Mirrors the runtime dedup rule.
var _runtime_error_dedup: Dictionary = {}
var _runtime_error_ordinal := 0
## T025: Outstanding pause tracking and decision log.
var _active_pause := {}
var _pause_decision_log: Array = []


func configure(plugin: EditorPlugin, bridge: Object, artifact_store: ScenegraphAutomationArtifactStore) -> void:
	_plugin = plugin
	_bridge = bridge
	_artifact_store = artifact_store
	if _bridge != null and _bridge.has_signal("runtime_error_record_received"):
		if not _bridge.runtime_error_record_received.is_connected(_on_runtime_error_record):
			_bridge.runtime_error_record_received.connect(_on_runtime_error_record)


func is_active() -> bool:
	return _active


func is_awaiting_runtime() -> bool:
	return _awaiting_runtime


func get_active_request() -> Dictionary:
	return _active_request.duplicate(true)


func start_run(config: Dictionary, request: Dictionary, capability: Dictionary, config_path: String = "") -> Dictionary:
	_active_config = config.duplicate(true)
	_active_request = _resolve_request(config, request, capability)
	_active_capability = capability.duplicate(true)
	_active_config_path = config_path
	_last_manifest = {}
	_last_validation = _build_validation_result(false, 0, [], false, ["Validation has not completed yet."])
	_last_build_failure = {}
	_last_error_anchor = {}
	_runtime_error_record_count = 0
	_runtime_error_dedup = {}
	_runtime_error_ordinal = 0
	_active_pause = {}
	_pause_decision_log = []
	_pending_failure_kind = null
	_pending_failure_message = ""
	_stop_requested = false
	_awaiting_stop = false

	var watch_validation := _active_request.get("behaviorWatchValidation", {})
	if not watch_validation.is_empty() and not bool(watch_validation.get("accepted", false)):
		return _finish_invalid_request(watch_validation)

	var input_dispatch_validation := _active_request.get("inputDispatchValidation", {})
	if not input_dispatch_validation.is_empty() and not bool(input_dispatch_validation.get("accepted", false)):
		return _finish_invalid_input_dispatch(input_dispatch_validation)

	var blocked_reasons := _collect_blocked_reasons(capability)
	if not blocked_reasons.is_empty():
		return _finish_blocked_run(blocked_reasons)

	_active = true
	_launch_started_at_usec = Time.get_ticks_usec()
	var request_id := String(_active_request.get("requestId", ""))
	var run_id := String(_active_request.get("runId", ""))
	_emit_status(InspectionConstants.AUTOMATION_STATUS_RECEIVED, "Autonomous run request accepted.")
	_emit_status(InspectionConstants.AUTOMATION_STATUS_LAUNCHING, "Starting the requested scene in the editor.")

	_bridge.set_session_context(_build_session_context())
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return _finish_blocked_run(["editor_interface_unavailable"])
	editor_interface.play_custom_scene(String(_active_request.get("targetScene", "")))
	if not _active:
		return {
			"ok": false,
			"requestId": request_id,
			"runId": run_id,
		}

	_emit_status(InspectionConstants.AUTOMATION_STATUS_AWAITING_RUNTIME, "Waiting for the runtime debugger session to attach.")
	_awaiting_runtime = true
	_awaiting_capture = true
	_awaiting_manifest = false
	return {
		"ok": true,
		"requestId": request_id,
		"runId": run_id,
	}


func poll() -> void:
	if not _active:
		return

	if _awaiting_runtime:
		var elapsed_usec := Time.get_ticks_usec() - _launch_started_at_usec
		if elapsed_usec > 15000000:
			_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, "Runtime debugger session did not attach before timeout.")
			return

	# T025: Check pause decision timeout (30 s default → stop).
	if not _active_pause.is_empty():
		var timeout_at: int = int(_active_pause.get("_timeoutAt", 0))
		if timeout_at > 0 and Time.get_ticks_msec() >= timeout_at:
			var now_ms := Time.get_ticks_msec()
			var raised_ms: int = int(_active_pause.get("_raisedAtMs", now_ms))
			var timeout_row := {
				"runId": String(_active_pause.get("runId", "")),
				"pauseId": int(_active_pause.get("pauseId", 0)),
				"cause": String(_active_pause.get("cause", "")),
				"scriptPath": String(_active_pause.get("scriptPath", "unknown")),
				"line": _active_pause.get("line"),
				"function": _active_pause.get("function"),
				"message": String(_active_pause.get("message", "")),
				"processFrame": int(_active_pause.get("processFrame", 0)),
				"raisedAt": String(_active_pause.get("raisedAt", "")),
				"decision": InspectionConstants.PAUSE_DECISION_TIMEOUT_DEFAULT_APPLIED,
				"decisionSource": InspectionConstants.PAUSE_DECISION_SOURCE_TIMEOUT_DEFAULT,
				"recordedAt": InspectionConstants.utc_timestamp_now(),
				"latencyMs": now_ms - raised_ms,
			}
			_pause_decision_log.append(timeout_row)
			_active_pause = {}
			# Apply timeout default: stop the run.
			_request_stop()
			return

	if _awaiting_stop and not _is_playing_scene():
		_finalize_after_stop(InspectionConstants.AUTOMATION_TERMINATION_STOPPED_CLEANLY)


func handle_session_state_changed(state: String, details: String) -> void:
	if not _active:
		return

	match state:
		InspectionConstants.SESSION_STATUS_CONNECTED:
			_on_runtime_attached()
		"disconnected":
			# T025: record stopped_by_disconnect if a pause was outstanding at disconnect.
			if not _active_pause.is_empty():
				var now_ms := Time.get_ticks_msec()
				var raised_ms: int = int(_active_pause.get("_raisedAtMs", now_ms))
				var disc_row := {
					"runId": String(_active_pause.get("runId", "")),
					"pauseId": int(_active_pause.get("pauseId", 0)),
					"cause": String(_active_pause.get("cause", "")),
					"scriptPath": String(_active_pause.get("scriptPath", "unknown")),
					"line": _active_pause.get("line"),
					"function": _active_pause.get("function"),
					"message": String(_active_pause.get("message", "")),
					"processFrame": int(_active_pause.get("processFrame", 0)),
					"raisedAt": String(_active_pause.get("raisedAt", "")),
					"decision": InspectionConstants.PAUSE_DECISION_STOPPED_BY_DISCONNECT,
					"decisionSource": InspectionConstants.PAUSE_DECISION_SOURCE_DISCONNECT,
					"recordedAt": InspectionConstants.utc_timestamp_now(),
					"latencyMs": now_ms - raised_ms,
				}
				_pause_decision_log.append(disc_row)
				_active_pause = {}
			if _awaiting_stop or _stop_requested:
				_finalize_after_stop(InspectionConstants.AUTOMATION_TERMINATION_STOPPED_CLEANLY)
			elif _awaiting_runtime:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, details)
			elif _last_manifest.is_empty():
				# T031: Abnormal disconnect with no manifest → classify as crashed.
				# The coordinator reads _last_error_anchor (or the sidecar) and
				# records the termination = crashed in the run result.
				_fail_run_as_crashed()
			elif _pending_failure_kind != null:
				# Fix #18: a deferred validation failure was recorded while
				# stopAfterValidation=false.  Now that the session has ended
				# normally, promote it to a hard failure so the run result is
				# correctly written as failed (not stuck at terminationStatus
				# "running") and runtime-error-records written during the deferred
				# window are preserved in the manifest.
				_fail_run(String(_pending_failure_kind), _pending_failure_message)
		InspectionConstants.SESSION_STATUS_ERROR:
			if _awaiting_runtime:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, details)
			elif _awaiting_manifest or _awaiting_capture:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_CAPTURE, details)
			else:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY, details)
		_:
			pass


func handle_capture_updated(snapshot: Dictionary, diagnostics: Array) -> void:
	if not _active or not _awaiting_capture:
		return

	_awaiting_capture = false
	_emit_status(InspectionConstants.AUTOMATION_STATUS_CAPTURING, "Scenegraph evidence capture completed.", {
		"evidenceRefs": _build_snapshot_refs(snapshot, diagnostics),
	})
	_emit_status(InspectionConstants.AUTOMATION_STATUS_PERSISTING, "Persisting the latest scenegraph evidence bundle.")
	_awaiting_manifest = true
	var termination := _derive_runtime_termination()
	if _bridge.has_method("persist_latest_bundle_with_context"):
		_bridge.persist_latest_bundle_with_context(_pause_decision_log, termination)
	elif _bridge.has_method("persist_latest_bundle_with_pause_log"):
		_bridge.persist_latest_bundle_with_pause_log(_pause_decision_log)
	else:
		_bridge.persist_latest_bundle()


func handle_manifest_persisted(manifest: Dictionary) -> void:
	if not _active or not _awaiting_manifest:
		return

	# T025: If a pause was still outstanding when the run ended, record resolved_by_run_end.
	if not _active_pause.is_empty():
		var now_ms := Time.get_ticks_msec()
		var raised_ms: int = int(_active_pause.get("_raisedAtMs", now_ms))
		var rre_row := {
			"runId": String(_active_pause.get("runId", "")),
			"pauseId": int(_active_pause.get("pauseId", 0)),
			"cause": String(_active_pause.get("cause", "")),
			"scriptPath": String(_active_pause.get("scriptPath", "unknown")),
			"line": _active_pause.get("line"),
			"function": _active_pause.get("function"),
			"message": String(_active_pause.get("message", "")),
			"processFrame": int(_active_pause.get("processFrame", 0)),
			"raisedAt": String(_active_pause.get("raisedAt", "")),
			"decision": InspectionConstants.PAUSE_DECISION_RESOLVED_BY_RUN_END,
			"decisionSource": InspectionConstants.PAUSE_DECISION_SOURCE_RUN_END,
			"recordedAt": InspectionConstants.utc_timestamp_now(),
			"latencyMs": now_ms - raised_ms,
		}
		_pause_decision_log.append(rre_row)
		_active_pause = {}

	_awaiting_manifest = false
	_last_manifest = manifest.duplicate(true)
	_emit_status(InspectionConstants.AUTOMATION_STATUS_VALIDATING, "Validating the persisted evidence bundle.")
	_last_validation = _validate_manifest(manifest)
	if not bool(_last_validation.get("bundleValid", false)):
		_pending_failure_kind = InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION
		_pending_failure_message = "Persisted evidence bundle failed validation."

	if _should_stop_after_validation():
		_request_stop()
		return

	if _pending_failure_kind != null:
		# stopAfterValidation is false: defer finalization so the coordinator stays
		# active to continue capturing runtime error records, pause events, and the
		# disconnect.  _fail_run will be called from handle_session_state_changed
		# when the session disconnects.
		_emit_status(InspectionConstants.AUTOMATION_STATUS_VALIDATING,
				"Evidence bundle failed validation; deferring failure — coordinator remains active.", {
					"failureKind": String(_pending_failure_kind),
				})
		return

	_finalize_run("completed", null, InspectionConstants.AUTOMATION_TERMINATION_RUNNING)


func handle_runtime_session_configured(session_context: Dictionary) -> void:
	if not _active:
		return
	if session_context.has("appliedWatch") and typeof(session_context.get("appliedWatch")) == TYPE_DICTIONARY:
		_active_request["appliedWatch"] = session_context.get("appliedWatch", {}).duplicate(true)
	if session_context.has("appliedInputDispatch") and typeof(session_context.get("appliedInputDispatch")) == TYPE_DICTIONARY:
		_active_request["appliedInputDispatch"] = session_context.get("appliedInputDispatch", {}).duplicate(true)


func handle_transport_error(message: String) -> void:
	if not _active:
		return

	if _awaiting_runtime:
		_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, message)
	elif _awaiting_manifest or _awaiting_capture:
		_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_CAPTURE, message)
	else:
		_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY, message)


func _on_runtime_error_record(record: Dictionary) -> void:
	## Called when the bridge forwards a structured runtime error record (T018).
	## Maintains the last-error anchor for crash classification (US3/T031).
	## Fix #19: also accumulates into _runtime_error_dedup for emergency persist.
	if not _active:
		return
	_runtime_error_record_count += 1
	# Comment 6: guard severity to the two allowed enum values.
	var severity := String(record.get("severity", ""))
	if severity != InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR and severity != InspectionConstants.RUNTIME_ERROR_SEVERITY_WARNING:
		severity = InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR
	if severity == InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR:
		_last_error_anchor = {
			"scriptPath": String(record.get("scriptPath", "unknown")),
			"line": record.get("line"),
			"severity": severity,
			"message": String(record.get("message", "")),
		}
	var script_path := String(record.get("scriptPath", "unknown"))
	var line: int = int(record.get("line", -1))
	# Comment 5: normalize line/function to schema-valid values.
	var norm_line = line if line >= 1 else null
	var raw_func = record.get("function")
	var norm_func = raw_func if (raw_func != null and String(raw_func).length() > 0) else null
	var dedup_key := "%s|%d|%s" % [script_path, line, severity]
	var now_ts := InspectionConstants.utc_timestamp_now()
	if _runtime_error_dedup.has(dedup_key):
		var existing: Dictionary = _runtime_error_dedup[dedup_key]
		var count: int = int(existing.get("repeatCount", 1))
		if count < InspectionConstants.RUNTIME_ERROR_REPEAT_CAP:
			existing["repeatCount"] = count + 1
			existing["lastSeenAt"] = now_ts
		else:
			existing["truncatedAt"] = InspectionConstants.RUNTIME_ERROR_REPEAT_CAP
	else:
		_runtime_error_ordinal += 1
		_runtime_error_dedup[dedup_key] = {
			"runId": String(record.get("runId", String(_active_request.get("runId", "")))),
			"ordinal": _runtime_error_ordinal,
			"scriptPath": script_path,
			"line": norm_line,
			"function": norm_func,
			"message": String(record.get("message", "")),
			"severity": severity,
			"firstSeenAt": now_ts,
			"lastSeenAt": now_ts,
			"repeatCount": 1,
		}


## T025: Called when the runtime raises a debug pause.
func handle_pause_raised(pause_msg: Dictionary) -> void:
	if not _active:
		return
	_active_pause = pause_msg.duplicate(true)
	_active_pause["_raisedAtMs"] = Time.get_ticks_msec()
	_active_pause["_timeoutAt"] = _active_pause["_raisedAtMs"] + (InspectionConstants.PAUSE_DECISION_TIMEOUT_SECONDS * 1000)


## T025: Called when the broker dispatches a valid pause decision to the runtime.
func handle_pause_decision_submitted(decision_msg: Dictionary) -> void:
	if _active_pause.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var raised_ms: int = int(_active_pause.get("_raisedAtMs", now_ms))
	var row := {
		"runId": String(_active_pause.get("runId", "")),
		"pauseId": int(_active_pause.get("pauseId", 0)),
		"cause": String(_active_pause.get("cause", "")),
		"scriptPath": String(_active_pause.get("scriptPath", "unknown")),
		"line": _active_pause.get("line"),
		"function": _active_pause.get("function"),
		"message": String(_active_pause.get("message", "")),
		"processFrame": int(_active_pause.get("processFrame", 0)),
		"raisedAt": String(_active_pause.get("raisedAt", "")),
		"decision": String(decision_msg.get("decision", "")),
		"decisionSource": InspectionConstants.PAUSE_DECISION_SOURCE_AGENT,
		"recordedAt": InspectionConstants.utc_timestamp_now(),
		"latencyMs": now_ms - raised_ms,
	}
	_pause_decision_log.append(row)
	_active_pause = {}


## T025: Called when the runtime acks a pause decision.
func handle_pause_decision_ack(ack: Dictionary) -> void:
	# Nothing extra needed here; the decision log row is written by handle_pause_decision_submitted.
	pass


func handle_build_failed(payload: Dictionary) -> void:
	if not _active:
		return

	_last_build_failure = _artifact_store.normalize_build_failure_payload(payload)
	_awaiting_runtime = false
	_awaiting_capture = false
	_awaiting_manifest = false

	var details := String(_last_build_failure.get("details", "Build diagnostics were detected before runtime attachment."))
	_last_validation = _build_build_failure_validation_result(details)
	_emit_status(
		InspectionConstants.AUTOMATION_STATUS_FAILED,
		details,
		_artifact_store.build_build_failure_status_extras(
			String(_last_build_failure.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING)),
			_last_build_failure.get("buildDiagnostics", []),
			_last_build_failure.get("rawBuildOutput", [])
		)
	)
	_finalize_run(
		"failed",
		InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD,
		_derive_build_failure_termination_status(),
		details,
		_last_build_failure
	)


func _on_runtime_attached() -> void:
	_awaiting_runtime = false
	var capture_policy: Dictionary = _active_request.get("capturePolicy", {})
	var startup_enabled := bool(capture_policy.get("startup", false))
	var manual_enabled := bool(capture_policy.get("manual", false))

	if startup_enabled:
		_emit_status(InspectionConstants.AUTOMATION_STATUS_CAPTURING, "Runtime debugger session attached; waiting for startup capture.")
		return

	if manual_enabled:
		_emit_status(InspectionConstants.AUTOMATION_STATUS_CAPTURING, "Runtime debugger session attached; requesting manual capture.")
		_bridge.request_manual_capture()
		return

	_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_CAPTURE, "Autonomous capture is disabled by the current capture policy.")


func _request_stop() -> void:
	_stop_requested = true
	_awaiting_stop = true
	_emit_status(InspectionConstants.AUTOMATION_STATUS_STOPPING, "Stopping the editor play session after validation.")
	var editor_interface = _get_editor_interface()
	if editor_interface != null:
		editor_interface.stop_playing_scene()
	if not _active or not _awaiting_stop:
		return
	if not _is_playing_scene():
		_finalize_after_stop(InspectionConstants.AUTOMATION_TERMINATION_STOPPED_CLEANLY)


func _finalize_after_stop(termination_status: String) -> void:
	if not _active:
		return
	_awaiting_stop = false
	if _pending_failure_kind != null:
		_finalize_run("failed", String(_pending_failure_kind), termination_status, _pending_failure_message)
		return

	_finalize_run("completed", null, termination_status)


func _finish_blocked_run(blocked_reasons: Array) -> Dictionary:
	var request_id := String(_active_request.get("requestId", "request-blocked"))
	var run_id := String(_active_request.get("runId", "run-blocked"))
	_emit_status(InspectionConstants.AUTOMATION_STATUS_BLOCKED, "Autonomous run request was blocked.", {
		"evidenceRefs": blocked_reasons,
	})
	var result := {
		"requestId": request_id,
		"runId": run_id,
		"finalStatus": "blocked",
		"failureKind": null,
		"manifestPath": null,
		"outputDirectory": String(_active_request.get("outputDirectory", "")),
		"validationResult": _build_validation_result(false, 0, [], false, ["Run was blocked before evidence validation could begin."]),
		"terminationStatus": InspectionConstants.AUTOMATION_TERMINATION_BLOCKED,
		"blockedReasons": blocked_reasons.duplicate(true),
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"completedAt": InspectionConstants.utc_timestamp_now(),
	}
	_artifact_store.write_run_result(_active_config, result)
	emit_signal("run_completed", result)
	_reset_state()
	return result


func _finish_invalid_request(validation_result: Dictionary) -> Dictionary:
	var request_id := String(_active_request.get("requestId", "request-invalid"))
	var run_id := String(_active_request.get("runId", "run-invalid"))
	var notes: Array = []
	for error_value in validation_result.get("errors", []):
		if typeof(error_value) != TYPE_DICTIONARY:
			continue
		var error: Dictionary = error_value
		notes.append("Behavior watch rejection: %s [%s] %s" % [
			String(error.get("code", "")),
			String(error.get("field", "")),
			String(error.get("message", "")),
		])
	if notes.is_empty():
		notes.append("Behavior watch request was rejected before playtest launch.")
	_emit_status(
		InspectionConstants.AUTOMATION_STATUS_FAILED,
		"Behavior watch request was rejected before playtest launch.",
		{
			"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION,
			"behaviorWatchValidation": validation_result.duplicate(true),
		}
	)
	var result := {
		"requestId": request_id,
		"runId": run_id,
		"finalStatus": "failed",
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION,
		"manifestPath": null,
		"outputDirectory": String(_active_request.get("outputDirectory", "")),
		"validationResult": _build_validation_result(false, 0, [], false, notes),
		"terminationStatus": InspectionConstants.AUTOMATION_TERMINATION_NOT_STARTED,
		"blockedReasons": [],
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"completedAt": InspectionConstants.utc_timestamp_now(),
	}
	_artifact_store.write_run_result(_active_config, result)
	emit_signal("run_completed", result)
	_reset_state()
	return {
		"ok": false,
		"requestId": request_id,
		"runId": run_id,
	}


func _fail_run(failure_kind: String, message: String) -> void:
	_emit_status(InspectionConstants.AUTOMATION_STATUS_FAILED, message, {
		"failureKind": failure_kind,
	})

	if _should_stop_after_validation() and _is_playing_scene() and not _stop_requested:
		_pending_failure_kind = failure_kind
		_pending_failure_message = message
		_request_stop()
		return

	_finalize_run("failed", failure_kind, _derive_failure_termination_status(), message)


## Fix #19: Emergency persist of any in-memory error records accumulated by
## _on_runtime_error_record when the run ends abnormally before the runtime
## had a chance to write runtime-error-records.jsonl itself.  Only writes
## when the target file is missing or empty so a runtime-written file is never
## overwritten.
func _emergency_persist_runtime_errors() -> void:
	var output_dir := String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var abs_dir: String
	if output_dir.begins_with("res://"):
		var project_path := ProjectSettings.globalize_path("res://")
		abs_dir = output_dir.replace("res://", project_path)
	else:
		abs_dir = output_dir
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var vn: Array = _last_validation.get("notes", []).duplicate(true)
	if _runtime_error_dedup.is_empty():
		if not "runtime_error_records: none_observed" in vn:
			vn.append("runtime_error_records: none_observed")
		_last_validation["notes"] = vn
		return
	var jsonl_path := abs_dir.path_join(InspectionConstants.DEFAULT_RUNTIME_ERROR_RECORDS_FILE)
	var should_write := not FileAccess.file_exists(jsonl_path)
	if not should_write:
		var fh := FileAccess.open(jsonl_path, FileAccess.READ)
		if fh != null:
			should_write = fh.get_length() == 0
			fh.close()
	if should_write:
		var records: Array = _runtime_error_dedup.values().duplicate(true)
		records.sort_custom(func(a, b): return int(a.get("ordinal", 0)) < int(b.get("ordinal", 0)))
		var fh := FileAccess.open(jsonl_path, FileAccess.WRITE)
		if fh != null:
			for r in records:
				fh.store_line(JSON.stringify(r))
			fh.close()
	# Comment 1: always stamp when records exist, independent of whether a write was
	# needed — the runtime may have already written the file on a clean exit.
	if not "runtime_error_records: emergency_persisted" in vn:
		vn.append("runtime_error_records: emergency_persisted")
	_last_validation["notes"] = vn
	if not _last_error_anchor.is_empty():
		var anchor_path := abs_dir.path_join(InspectionConstants.DEFAULT_LAST_ERROR_ANCHOR_FILE)
		if not FileAccess.file_exists(anchor_path):
			var fh := FileAccess.open(anchor_path, FileAccess.WRITE)
			if fh != null:
				fh.store_string(JSON.stringify(_last_error_anchor))
				fh.close()


## T031: Called on abnormal disconnect (no manifest, no stop request).
## Reads the coordinator's in-memory last-error anchor (populated by _on_runtime_error_record)
## or the on-disk sidecar written by T030, and finalizes the run with termination = crashed.
func _fail_run_as_crashed() -> void:
	# Fix #19: flush any in-memory error records the runtime never got to persist.
	_emergency_persist_runtime_errors()
	var anchor := _last_error_anchor.duplicate(true)
	# Also try reading the sidecar from disk as a recovery fallback.
	if anchor.is_empty():
		anchor = _read_last_error_anchor_sidecar()
	var crash_message := "The play session ended abnormally before a scenegraph bundle was persisted."
	_emit_status(InspectionConstants.AUTOMATION_STATUS_FAILED, crash_message, {
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY,
		"termination": InspectionConstants.RUNTIME_TERMINATION_CRASHED,
		"lastErrorAnchor": anchor if not anchor.is_empty() else {"lastError": "none"},
	})
	_finalize_run(
		"failed",
		InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY,
		InspectionConstants.AUTOMATION_TERMINATION_CRASHED,
		crash_message
	)


func _read_last_error_anchor_sidecar() -> Dictionary:
	var output_dir := String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	# Editor-side: convert res:// to an absolute path via the project root.
	var abs_dir: String
	if output_dir.begins_with("res://"):
		var project_path := ProjectSettings.globalize_path("res://")
		abs_dir = output_dir.replace("res://", project_path)
	else:
		abs_dir = output_dir
	var sidecar_path := abs_dir.path_join(InspectionConstants.DEFAULT_LAST_ERROR_ANCHOR_FILE)
	if not FileAccess.file_exists(sidecar_path):
		return {}
	var handle := FileAccess.open(sidecar_path, FileAccess.READ)
	if handle == null:
		return {}
	var parsed := JSON.parse_string(handle.get_as_text())
	handle.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _finalize_run(final_status: String, failure_kind, termination_status: String, note := "", build_failure := {}) -> void:
	var manifest_path = null
	if not _last_manifest.is_empty():
		manifest_path = _resolve_manifest_repo_path()
	var validation_result := _last_validation.duplicate(true)
	if not note.is_empty():
		var validation_notes: Array = validation_result.get("notes", []).duplicate(true)
		if not note in validation_notes:
			validation_notes.append(note)
		validation_result["notes"] = validation_notes

	var result := {
		"requestId": String(_active_request.get("requestId", "")),
		"runId": String(_active_request.get("runId", "")),
		"finalStatus": final_status,
		"failureKind": failure_kind,
		"manifestPath": manifest_path,
		"outputDirectory": String(_active_request.get("outputDirectory", "")),
		"validationResult": validation_result,
		"terminationStatus": termination_status,
		"blockedReasons": [],
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"completedAt": InspectionConstants.utc_timestamp_now(),
	}
	if failure_kind == InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD:
		var normalized_build_failure: Dictionary = _artifact_store.normalize_build_failure_payload(build_failure)
		result["buildFailurePhase"] = normalized_build_failure.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING)
		result["buildDiagnostics"] = normalized_build_failure.get("buildDiagnostics", []).duplicate(true)
		result["rawBuildOutput"] = normalized_build_failure.get("rawBuildOutput", []).duplicate(true)
	var terminal_extras := {}
	if manifest_path != null:
		terminal_extras["evidenceRefs"] = [String(manifest_path)]
	if failure_kind != null:
		terminal_extras["failureKind"] = failure_kind
	if failure_kind == InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD:
		terminal_extras["buildFailurePhase"] = result.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING)
		terminal_extras["buildDiagnosticCount"] = result.get("buildDiagnostics", []).size()
		terminal_extras["rawBuildOutputAvailable"] = not result.get("rawBuildOutput", []).is_empty()
	var terminal_status := InspectionConstants.AUTOMATION_STATUS_COMPLETED
	var terminal_details := "Autonomous run completed."
	if final_status != "completed":
		terminal_status = InspectionConstants.AUTOMATION_STATUS_FAILED
		terminal_details = "Autonomous run failed."
	if not note.is_empty():
		terminal_details = note
	_emit_status(terminal_status, terminal_details, terminal_extras)
	_artifact_store.write_run_result(_active_config, result)
	emit_signal("run_completed", result)
	_reset_state()


func _emit_status(status: String, details: String, extras := {}) -> void:
	var payload: Dictionary = _artifact_store.build_status_payload(
		String(_active_request.get("requestId", "request-pending")),
		String(_active_request.get("runId", "run-pending")),
		status,
		details,
		extras
	)
	_artifact_store.write_lifecycle_status(_active_config, payload)
	emit_signal("lifecycle_status_written", payload)


func _resolve_active_config_path() -> String:
	if not _active_config_path.is_empty():
		return _active_config_path

	for source in [_active_request, _active_config]:
		var camel_case_path := String(source.get("configPath", ""))
		if not camel_case_path.is_empty():
			return camel_case_path

		var snake_case_path := String(source.get("config_path", ""))
		if not snake_case_path.is_empty():
			return snake_case_path

	return "res://harness/inspection-run-config.json"


func _build_session_context() -> Dictionary:
	# T034: Determine pause_on_error_mode from capability snapshot at run start.
	var pause_on_error_cap: Dictionary = {}
	if typeof(_active_capability.get("pauseOnError", null)) == TYPE_DICTIONARY:
		pause_on_error_cap = _active_capability.get("pauseOnError", {})
	var pause_on_error_mode := InspectionConstants.PAUSE_ON_ERROR_MODE_ACTIVE if bool(pause_on_error_cap.get("supported", true)) else InspectionConstants.PAUSE_ON_ERROR_MODE_UNAVAILABLE_DEGRADED_CAPTURE_ONLY

	var context := {
		"config_path": _resolve_active_config_path(),
		"session_id": String(_active_request.get("requestId", "")),
		"request_id": String(_active_request.get("requestId", "")),
		"run_id": String(_active_request.get("runId", "")),
		"scenario_id": String(_active_request.get("scenarioId", InspectionConstants.DEFAULT_SCENARIO_ID)),
		"requested_by": String(_active_request.get("requestedBy", "scenegraph_automation_broker")),
		"output_directory": String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY)),
		"artifact_root": String(_active_request.get("artifactRoot", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT)),
		"capture_policy": _active_request.get("capturePolicy", {}).duplicate(true),
		"stop_policy": _active_request.get("stopPolicy", {}).duplicate(true),
		"pause_on_error_mode": pause_on_error_mode,
	}
	if _active_request.has("appliedWatch"):
		context["applied_watch"] = _active_request.get("appliedWatch", {}).duplicate(true)
	if _active_request.has("inputDispatchScript"):
		context[InspectionConstants.INPUT_DISPATCH_RUNTIME_KEY_APPLIED] = _active_request.get("inputDispatchScript", {}).duplicate(true)
	if _active_request.has("appliedInputDispatch"):
		context["applied_input_dispatch"] = _active_request.get("appliedInputDispatch", {}).duplicate(true)
	return context


func _collect_blocked_reasons(capability: Dictionary) -> Array:
	var blocked: Array = []
	for blocked_reason in capability.get("blockedReasons", []):
		blocked.append(String(blocked_reason))

	if String(_active_request.get("requestId", "")).is_empty():
		blocked.append("request_id_missing")
	if String(_active_request.get("runId", "")).is_empty():
		blocked.append("run_id_missing")
	if String(_active_request.get("targetScene", "")).is_empty():
		blocked.append("target_scene_missing")
	if _is_playing_scene():
		blocked.append("scene_already_running")

	var capture_policy: Dictionary = _active_request.get("capturePolicy", {})
	if not bool(capture_policy.get("startup", false)) and not bool(capture_policy.get("manual", false)):
		blocked.append("capture_policy_blocks_autonomous_capture")

	return _dedupe_strings(blocked)


func _resolve_request(config: Dictionary, request: Dictionary, capability: Dictionary = {}) -> Dictionary:
	# Precedence (highest wins): request.overrides > request > config.defaultRequestOverrides > config.
	# B8: an automation request that explicitly sets targetScene/outputDirectory/etc.
	# must override any inspection-run-config.json defaults. The previous code
	# initialized scalar fields from config and then layered request on top,
	# which surfaced subtle bugs whenever the request supplied fields the
	# config also pinned. Inline the precedence chain so it reads top-to-bottom.
	var overrides: Dictionary = request.get("overrides", {})
	var default_overrides: Dictionary = config.get("defaultRequestOverrides", {})
	var base_capture_policy: Dictionary = config.get("capturePolicy", {}).duplicate(true)
	var base_stop_policy := {"stopAfterValidation": true}

	var resolved := {
		"requestId": String(request.get("requestId", "request-%s" % str(Time.get_ticks_usec()))),
		"scenarioId": String(request.get("scenarioId", config.get("scenarioId", InspectionConstants.DEFAULT_SCENARIO_ID))),
		"runId": String(request.get("runId", config.get("runId", "run-%s" % str(Time.get_ticks_usec())))),
		"targetScene": _pick_scalar(overrides, request, default_overrides, config, "targetScene", ""),
		"outputDirectory": _pick_scalar(overrides, request, default_overrides, config, "outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY),
		"artifactRoot": _pick_scalar(overrides, request, default_overrides, config, "artifactRoot", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT),
		"expectationFiles": _copy_array(config.get("expectationFiles", [])),
		"capturePolicy": base_capture_policy,
		"stopPolicy": base_stop_policy,
		"requestedBy": String(request.get("requestedBy", "scenegraph_automation_broker")),
	}

	# Arrays and nested dicts still merge layer-by-layer (config -> default_overrides -> request -> overrides).
	_apply_array_override(resolved, default_overrides, "expectationFiles")
	_merge_nested_override(resolved, "capturePolicy", default_overrides.get("capturePolicy", {}))
	_merge_nested_override(resolved, "stopPolicy", default_overrides.get("stopPolicy", {}))

	_apply_array_override(resolved, request, "expectationFiles")
	_merge_nested_override(resolved, "capturePolicy", request.get("capturePolicy", {}))
	_merge_nested_override(resolved, "stopPolicy", request.get("stopPolicy", {}))

	_apply_array_override(resolved, overrides, "expectationFiles")
	_merge_nested_override(resolved, "capturePolicy", overrides.get("capturePolicy", {}))
	_merge_nested_override(resolved, "stopPolicy", overrides.get("stopPolicy", {}))

	var behavior_watch_request := _resolve_behavior_watch_request(default_overrides, request, overrides)
	if not behavior_watch_request.is_empty():
		var watch_validation := _watch_request_validator.normalize_request(behavior_watch_request, String(resolved.get("runId", "")))
		resolved["behaviorWatchValidation"] = watch_validation
		if bool(watch_validation.get("accepted", false)):
			resolved["behaviorWatchRequest"] = watch_validation.get("request", {}).duplicate(true)
			resolved["appliedWatch"] = watch_validation.get("appliedWatch", {}).duplicate(true)

	var input_dispatch_script := _resolve_input_dispatch_script(default_overrides, request, overrides)
	if not input_dispatch_script.is_empty():
		var declared_actions := _collect_declared_input_actions()
		var input_dispatch_capability := {}
		if typeof(capability.get("inputDispatch", null)) == TYPE_DICTIONARY:
			input_dispatch_capability = capability.get("inputDispatch", {}).duplicate(true)
		var dispatch_validation := _input_dispatch_validator.normalize_request(
			input_dispatch_script,
			String(resolved.get("runId", "")),
			declared_actions,
			input_dispatch_capability
		)
		resolved["inputDispatchValidation"] = dispatch_validation
		if bool(dispatch_validation.get("accepted", false)):
			resolved["inputDispatchScript"] = dispatch_validation.get("request", {}).duplicate(true)
			resolved["appliedInputDispatch"] = dispatch_validation.get("appliedDispatch", {}).duplicate(true)

	return resolved


func _resolve_input_dispatch_script(default_overrides: Dictionary, request: Dictionary, overrides: Dictionary) -> Dictionary:
	for source_value in [
		overrides.get("inputDispatchScript", null),
		request.get("inputDispatchScript", null),
		default_overrides.get("inputDispatchScript", null),
	]:
		if typeof(source_value) == TYPE_DICTIONARY and not (source_value as Dictionary).is_empty():
			return (source_value as Dictionary).duplicate(true)
	return {}


func _collect_declared_input_actions() -> Array:
	var actions: Array = []
	if not Engine.has_singleton("InputMap"):
		# InputMap is always available at runtime; this guard keeps tests safe.
		pass
	for action_name in InputMap.get_actions():
		actions.append(String(action_name))
	return actions


func _finish_invalid_input_dispatch(validation_result: Dictionary) -> Dictionary:
	var request_id := String(_active_request.get("requestId", "request-invalid"))
	var run_id := String(_active_request.get("runId", "run-invalid"))
	var notes: Array = []
	for error_value in validation_result.get("errors", []):
		if typeof(error_value) != TYPE_DICTIONARY:
			continue
		var error: Dictionary = error_value
		notes.append("Input dispatch rejection: %s [%s] %s" % [
			String(error.get("code", "")),
			String(error.get("field", "")),
			String(error.get("message", "")),
		])
	if notes.is_empty():
		notes.append("Input dispatch script was rejected before playtest launch.")
	_emit_status(
		InspectionConstants.AUTOMATION_STATUS_FAILED,
		"Input dispatch script was rejected before playtest launch.",
		{
			"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION,
			"inputDispatchValidation": validation_result.duplicate(true),
		}
	)
	var result := {
		"requestId": request_id,
		"runId": run_id,
		"finalStatus": "failed",
		"failureKind": InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION,
		"manifestPath": null,
		"outputDirectory": String(_active_request.get("outputDirectory", "")),
		"validationResult": _build_validation_result(false, 0, [], false, notes),
		"terminationStatus": InspectionConstants.AUTOMATION_TERMINATION_NOT_STARTED,
		"blockedReasons": [],
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"completedAt": InspectionConstants.utc_timestamp_now(),
		"inputDispatchValidation": validation_result.duplicate(true),
	}
	_artifact_store.write_run_result(_active_config, result)
	emit_signal("run_completed", result)
	_reset_state()
	return {
		"ok": false,
		"requestId": request_id,
		"runId": run_id,
	}


func _resolve_behavior_watch_request(default_overrides: Dictionary, request: Dictionary, overrides: Dictionary) -> Dictionary:
	var resolved := {}
	for source_value in [
		default_overrides.get("behaviorWatchRequest", null),
		request.get("behaviorWatchRequest", null),
		overrides.get("behaviorWatchRequest", null),
	]:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		for key_value in source.keys():
			var key := String(key_value)
			if key == "cadence" and typeof(source.get(key)) == TYPE_DICTIONARY:
				var cadence: Dictionary = resolved.get("cadence", {}).duplicate(true)
				for cadence_key in source.get(key, {}).keys():
					cadence[cadence_key] = source.get(key, {}).get(cadence_key)
				resolved["cadence"] = cadence
				continue
			resolved[key] = source.get(key)
	return resolved


func _apply_scalar_override(target: Dictionary, source: Dictionary, key: String) -> void:
	if source.has(key):
		target[key] = source.get(key)


# B8: Pick a scalar value by walking sources in highest-precedence-first order.
# A non-empty value at any layer wins; empty strings fall through to the next
# layer so a stale empty in the base layer doesn't trump a populated request
# field. The final fallback is the literal default.
func _pick_scalar(highest: Dictionary, mid_high: Dictionary, mid_low: Dictionary, lowest: Dictionary, key: String, fallback) -> String:
	for src in [highest, mid_high, mid_low, lowest]:
		if src is Dictionary and src.has(key):
			var v: String = String(src.get(key, ""))
			if not v.is_empty():
				return v
	return String(fallback)


func _apply_array_override(target: Dictionary, source: Dictionary, key: String) -> void:
	if source.has(key):
		target[key] = _copy_array(source.get(key, []))


func _merge_nested_override(target: Dictionary, key: String, source: Dictionary) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		return
	var merged: Dictionary = target.get(key, {}).duplicate(true)
	for nested_key in source.keys():
		merged[nested_key] = source[nested_key]
	target[key] = merged


func _copy_array(values: Array) -> Array:
	var copied: Array = []
	for value in values:
		copied.append(value)
	return copied


func _build_validation_result(manifest_exists: bool, artifact_refs_checked: int, missing_artifacts: Array, bundle_valid: bool, notes: Array) -> Dictionary:
	return {
		"manifestExists": manifest_exists,
		"artifactRefsChecked": artifact_refs_checked,
		"missingArtifacts": missing_artifacts.duplicate(true),
		"bundleValid": bundle_valid,
		"notes": notes.duplicate(true),
		"validatedAt": InspectionConstants.utc_timestamp_now(),
	}


func _build_build_failure_validation_result(note: String) -> Dictionary:
	var notes: Array = [
		"No new evidence manifest was produced because the run failed during build before runtime capture.",
	]
	var expected_manifest_path := _resolve_expected_manifest_resource_path()
	if FileAccess.file_exists(expected_manifest_path):
		notes.append("An existing manifest file was ignored so stale evidence would not be reported for this build-failed run.")
	if not note.is_empty():
		notes.append(note)
	return _build_validation_result(false, 0, [], false, notes)


func _validate_manifest(manifest: Dictionary) -> Dictionary:
	if manifest.is_empty():
		return _build_validation_result(false, 0, [], false, ["No manifest was produced for the autonomous run."])

	var missing_artifacts: Array = []
	var notes: Array = []
	var output_directory := String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var artifact_refs: Array = manifest.get("artifactRefs", [])
	for artifact_ref_value in artifact_refs:
		var artifact_ref: Dictionary = artifact_ref_value
		var expected_path := output_directory.path_join(String(artifact_ref.get("path", "")).get_file())
		if not FileAccess.file_exists(expected_path):
			missing_artifacts.append(String(artifact_ref.get("path", "")))

	var run_id_matches := String(manifest.get("runId", "")) == String(_active_request.get("runId", ""))
	var scenario_matches := String(manifest.get("scenarioId", "")) == String(_active_request.get("scenarioId", ""))
	if not run_id_matches:
		notes.append("Manifest runId did not match the active automation request.")
	if not scenario_matches:
		notes.append("Manifest scenarioId did not match the active automation request.")
	if missing_artifacts.is_empty():
		notes.append("Manifest and referenced scenegraph artifacts exist for the active run.")

	var artifact_refs_for_run: Array = manifest.get("artifactRefs", [])
	var applied_watch_valid := true
	if not _active_request.get("appliedWatch", {}).is_empty():
		var trace_path := _resolve_trace_repo_path()
		var trace_artifact_ref := _find_artifact_ref(artifact_refs_for_run, InspectionConstants.ARTIFACT_KIND_TRACE)
		var manifest_applied_watch: Dictionary = manifest.get("appliedWatch", {})
		if trace_artifact_ref.is_empty():
			applied_watch_valid = false
			notes.append("Manifest did not include a trace artifact reference for the active behavior watch.")
		elif String(trace_artifact_ref.get("path", "")) != trace_path:
			applied_watch_valid = false
			notes.append("Manifest trace artifact path did not match the active run's trace.jsonl path.")
		if manifest_applied_watch.is_empty():
			applied_watch_valid = false
			notes.append("Manifest did not include the applied behavior-watch summary for the active run.")
		elif String(manifest_applied_watch.get("runId", "")) != String(_active_request.get("runId", "")):
			applied_watch_valid = false
			notes.append("Manifest appliedWatch.runId did not match the active automation request.")

	var applied_input_dispatch_valid := true
	if not _active_request.get("appliedInputDispatch", {}).is_empty():
		var outcomes_artifact_ref := _find_artifact_ref(artifact_refs_for_run, InspectionConstants.ARTIFACT_KIND_INPUT_DISPATCH_OUTCOMES)
		var manifest_applied_input_dispatch: Dictionary = manifest.get("appliedInputDispatch", {})
		if outcomes_artifact_ref.is_empty():
			applied_input_dispatch_valid = false
			notes.append("Manifest did not include an input-dispatch outcome artifact reference for the active run.")
		if manifest_applied_input_dispatch.is_empty():
			applied_input_dispatch_valid = false
			notes.append("Manifest did not include the applied input-dispatch summary for the active run.")
		elif String(manifest_applied_input_dispatch.get("runId", "")) != String(_active_request.get("runId", "")):
			applied_input_dispatch_valid = false
			notes.append("Manifest appliedInputDispatch.runId did not match the active automation request.")

	for manifest_note_value in manifest.get("validation", {}).get("notes", []):
		var manifest_note := String(manifest_note_value)
		if manifest_note.is_empty() or manifest_note in notes:
			continue
		notes.append(manifest_note)

	var bundle_valid := run_id_matches and scenario_matches and missing_artifacts.is_empty() \
		and bool(manifest.get("validation", {}).get("bundleValid", false)) \
		and applied_watch_valid \
		and applied_input_dispatch_valid
	return _build_validation_result(true, artifact_refs.size(), missing_artifacts, bundle_valid, notes)


func _build_snapshot_refs(snapshot: Dictionary, diagnostics: Array) -> Array:
	var refs: Array = []
	if not snapshot.is_empty():
		refs.append(String(snapshot.get("snapshot_id", "")))
	if not diagnostics.is_empty():
		refs.append("diagnostics:%d" % diagnostics.size())
	return refs


func _derive_failure_termination_status() -> String:
	if _stop_requested:
		return InspectionConstants.AUTOMATION_TERMINATION_SHUTDOWN_FAILED
	if _is_playing_scene():
		return InspectionConstants.AUTOMATION_TERMINATION_RUNNING
	return InspectionConstants.AUTOMATION_TERMINATION_ALREADY_CLOSED


## T031: Derive the runtimeErrorReporting.termination value from the completed run state.
## This is sent to the runtime just before persist_latest_bundle so the artifact writer
## can stamp the manifest with the correct classification.
func _derive_runtime_termination() -> String:
	# Walk backward through the pause decision log for the first resolved decision
	# that produced a definitive termination cause.
	for i in range(_pause_decision_log.size() - 1, -1, -1):
		var row_val: Variant = _pause_decision_log[i]
		if typeof(row_val) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_val
		var decision := String(row.get("decision", ""))
		var source := String(row.get("decisionSource", ""))
		if decision == InspectionConstants.PAUSE_DECISION_STOPPED and source == InspectionConstants.PAUSE_DECISION_SOURCE_AGENT:
			return InspectionConstants.RUNTIME_TERMINATION_STOPPED_BY_AGENT
		if decision == InspectionConstants.PAUSE_DECISION_TIMEOUT_DEFAULT_APPLIED:
			return InspectionConstants.RUNTIME_TERMINATION_STOPPED_BY_DEFAULT_ON_PAUSE_TIMEOUT
	# Default: normal clean exit.
	return InspectionConstants.RUNTIME_TERMINATION_COMPLETED


func _derive_build_failure_termination_status() -> String:
	var build_failure_phase := String(_last_build_failure.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING))
	if _is_playing_scene():
		return InspectionConstants.AUTOMATION_TERMINATION_RUNNING
	if build_failure_phase == InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_AWAITING_RUNTIME:
		return InspectionConstants.AUTOMATION_TERMINATION_ALREADY_CLOSED
	return InspectionConstants.AUTOMATION_TERMINATION_NOT_STARTED


func _should_stop_after_validation() -> bool:
	var stop_policy: Dictionary = _active_request.get("stopPolicy", {})
	return bool(stop_policy.get("stopAfterValidation", true))


func _resolve_manifest_repo_path() -> String:
	var artifact_root := String(_active_request.get("artifactRoot", ""))
	if artifact_root.is_empty():
		artifact_root = String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY)).trim_prefix("res://")
	return artifact_root.path_join("evidence-manifest.json")


func _resolve_trace_repo_path() -> String:
	var artifact_root := String(_active_request.get("artifactRoot", ""))
	if artifact_root.is_empty():
		artifact_root = String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY)).trim_prefix("res://")
	return artifact_root.path_join(InspectionConstants.DEFAULT_BEHAVIOR_WATCH_TRACE_FILE)


func _resolve_expected_manifest_resource_path() -> String:
	var output_directory := String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	if not output_directory.is_empty():
		return output_directory.path_join("evidence-manifest.json")

	var artifact_root := String(_active_request.get("artifactRoot", ""))
	if artifact_root.begins_with("res://"):
		return artifact_root.path_join("evidence-manifest.json")

	return InspectionConstants.DEFAULT_OUTPUT_DIRECTORY.path_join("evidence-manifest.json")


func _dedupe_strings(values: Array) -> Array:
	var deduped: Array = []
	for value in values:
		var text := String(value)
		if text.is_empty() or text in deduped:
			continue
		deduped.append(text)
	return deduped


func _find_artifact_ref(artifact_refs: Array, kind: String) -> Dictionary:
	for artifact_ref_value in artifact_refs:
		var artifact_ref: Dictionary = artifact_ref_value
		if String(artifact_ref.get("kind", "")) == kind:
			return artifact_ref
	return {}


func _get_editor_interface():
	if _plugin == null:
		return null
	return _plugin.get_editor_interface()


func _is_playing_scene() -> bool:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return false
	return editor_interface.is_playing_scene()


func _reset_state() -> void:
	_active = false
	_awaiting_runtime = false
	_awaiting_capture = false
	_awaiting_manifest = false
	_awaiting_stop = false
	_stop_requested = false
	_pending_failure_kind = null
	_pending_failure_message = ""
	_last_build_failure = {}
	_active_config = {}
	_active_request = {}
	_last_manifest = {}
	_last_validation = {}
	_launch_started_at_usec = 0
	_active_config_path = ""
