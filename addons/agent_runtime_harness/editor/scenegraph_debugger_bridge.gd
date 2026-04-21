@tool
extends EditorDebuggerPlugin
class_name ScenegraphDebuggerBridge

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")

signal session_state_changed(state, details)
signal capture_updated(snapshot, diagnostics)
signal manifest_persisted(manifest)
signal transport_error(message)
signal automation_session_configured(session_context)
signal runtime_error_record_received(record)
signal runtime_pause_raised(pause_msg)
signal runtime_pause_decision_ack(ack)

var _session_context := {}
var _latest_snapshot := {}
var _latest_diagnostics: Array = []
var _known_session_ids: Array = []
var _active_session_id := -1


func set_session_context(session_context: Dictionary) -> void:
	_session_context = session_context.duplicate(true)
	_configure_active_session()


func _has_capture(capture: String) -> bool:
	return capture == InspectionConstants.RUNTIME_TO_EDITOR_CHANNEL or capture == "error"


func _setup_session(session_id: int) -> void:
	if session_id not in _known_session_ids:
		_known_session_ids.append(session_id)

	var session = get_session(session_id)
	if session == null:
		return

	session.started.connect(_on_session_started.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))

	if session.is_active():
		_on_session_started(session_id)


func _capture(message: String, data: Array, session_id: int) -> bool:
	# Handle the engine's built-in error channel.
	if message == "error":
		_on_engine_error(data, session_id)
		return true

	var event_name := message.trim_prefix("%s:" % InspectionConstants.RUNTIME_TO_EDITOR_CHANNEL)
	match event_name:
		"snapshot":
			if data.size() >= 2:
				_on_capture_ready(data[0], data[1])
			return true
		"persisted":
			if not data.is_empty():
				_on_persistence_completed(data[0])
			return true
		"session_configured":
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				_on_session_configured(data[0])
			return true
		"runtime_error":
			# Deprecated path: the old unstructured runtime_error message.
			# Now handled as a transport error only if the data is a plain string.
			if not data.is_empty() and typeof(data[0]) == TYPE_STRING:
				_on_runtime_error(String(data[0]))
			return true
		InspectionConstants.RUNTIME_ERROR_MSG_RECORD:
			# The runtime sends back its first-occurrence records so the editor
			# can maintain the real-time anchor for crash classification.
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				emit_signal("runtime_error_record_received", data[0])
			return true
		InspectionConstants.RUNTIME_ERROR_MSG_PAUSE:
			# The runtime raised a pause (T023); forward to run coordinator.
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				emit_signal("runtime_pause_raised", data[0])
			return true
		InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION_ACK:
			# The runtime acknowledged or rejected a pause decision (T023).
			if not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
				emit_signal("runtime_pause_decision_ack", data[0])
			return true
		_:
			return false


func request_manual_capture() -> void:
	_send_request("request_manual_capture")


func request_failure_capture(reason: String) -> void:
	_send_request("request_failure_capture", [reason])


func persist_latest_bundle() -> void:
	_send_request("persist_latest_bundle")


func persist_latest_bundle_with_pause_log(pause_decision_log: Array) -> void:
	## T025/T026: Send the pause decision log to the runtime before persisting,
	## so the artifact writer can flush it to pause-decision-log.jsonl.
	if not pause_decision_log.is_empty():
		_send_request(InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION_LOG, [pause_decision_log])
	_send_request("persist_latest_bundle")


func persist_latest_bundle_with_context(pause_decision_log: Array, termination: String) -> void:
	## T031: Send pause decision log and termination classification to runtime
	## so the artifact writer can stamp them in the manifest.
	if not pause_decision_log.is_empty():
		_send_request(InspectionConstants.RUNTIME_ERROR_MSG_PAUSE_DECISION_LOG, [pause_decision_log])
	if not termination.is_empty():
		_send_request(InspectionConstants.RUNTIME_ERROR_MSG_SET_TERMINATION, [termination])
	_send_request("persist_latest_bundle")


func get_latest_snapshot() -> Dictionary:
	return _latest_snapshot.duplicate(true)


func get_latest_diagnostics() -> Array:
	return _latest_diagnostics.duplicate(true)


func has_active_session() -> bool:
	return _get_active_session() != null


func get_active_session_id() -> int:
	if _get_active_session() == null:
		return -1
	return _active_session_id


func _on_capture_ready(snapshot: Dictionary, diagnostics: Array) -> void:
	_latest_snapshot = snapshot.duplicate(true)
	_latest_diagnostics = diagnostics.duplicate(true)
	emit_signal("session_state_changed", "capturing", "Scenegraph snapshot received.")
	emit_signal("capture_updated", _latest_snapshot, _latest_diagnostics)


func _on_persistence_completed(manifest: Dictionary) -> void:
	emit_signal("session_state_changed", "persisted", "Scenegraph evidence bundle written.")
	emit_signal("manifest_persisted", manifest)


func _on_session_configured(session_context: Dictionary) -> void:
	emit_signal("session_state_changed", "configured", "Runtime automation session configured.")
	emit_signal("automation_session_configured", session_context)


func _on_runtime_error(message: String) -> void:
	_emit_transport_error(message)


func _on_engine_error(data: Array, session_id: int) -> void:
	## Godot 4 sends the built-in "error" message with an array of fields.
	## The standard layout (subject to Godot version) is:
	##   [0] callstack_size: int
	##   [1] callstack: Array of { "source", "line", "func" }
	##   [2] hr: int  (HResult / error code)
	##   [3] source_file: String
	##   [4] source_func: String
	##   [5] source_line: int
	##   [6] error: String (human-readable message)
	##   [7] error_descr: String (detailed description, may be empty)
	##   [8] warning: bool  (true = push_warning, false = push_error / runtime error)
	## The layout can vary; extract defensively.
	if data.is_empty():
		return

	var source_file := ""
	var source_func := ""
	var source_line := -1
	var message := ""
	var is_warning := false

	if data.size() >= 9:
		source_file = String(data[3])
		source_func = String(data[4])
		source_line = int(data[5])
		message = String(data[6])
		var descr := String(data[7])
		if not descr.is_empty():
			message = "%s: %s" % [message, descr]
		is_warning = bool(data[8])
	elif data.size() >= 7:
		source_file = String(data[3])
		source_func = String(data[4])
		source_line = int(data[5])
		message = String(data[6])
	else:
		# Unknown layout — emit a generic transport error and bail.
		return

	var severity: String = InspectionConstants.RUNTIME_ERROR_SEVERITY_WARNING if is_warning else InspectionConstants.RUNTIME_ERROR_SEVERITY_ERROR
	var record := {
		"scriptPath": source_file if not source_file.is_empty() else "unknown",
		"line": source_line if source_line > 0 else null,
		"function": source_func if not source_func.is_empty() else null,
		"message": message,
		"severity": severity,
	}

	# Forward the structured record to the runtime via the editor channel so the
	# runtime can update its dedup map and eventually flush to JSONL.
	_send_request(InspectionConstants.RUNTIME_ERROR_MSG_RECORD, [record])

	# Also emit locally so the run coordinator can track the anchor in real time.
	emit_signal("runtime_error_record_received", record)


func _emit_transport_error(message: String) -> void:
	emit_signal("session_state_changed", "error", message)
	emit_signal("transport_error", message)


func _on_session_started(session_id: int) -> void:
	_active_session_id = session_id
	emit_signal("session_state_changed", InspectionConstants.SESSION_STATUS_CONNECTED, "Runtime debugger session attached.")
	_configure_active_session()


func _on_session_stopped(session_id: int) -> void:
	if _active_session_id == session_id:
		_active_session_id = -1
	emit_signal("session_state_changed", "disconnected", "Runtime debugger session detached.")


func _configure_active_session() -> void:
	if _session_context.is_empty():
		return
	_send_request("configure_session", [_session_context], false)


func _send_request(request_name: String, payload: Array = [], report_missing_session := true) -> void:
	var session = _get_active_session()
	if session == null:
		if report_missing_session:
			_emit_transport_error("%s requested before a runtime debugger session was attached." % request_name)
		return

	session.send_message("%s:%s" % [InspectionConstants.EDITOR_TO_RUNTIME_CHANNEL, request_name], payload)


func _get_active_session():
	if _active_session_id >= 0:
		var active_session = get_session(_active_session_id)
		if active_session != null and active_session.is_active():
			return active_session

	for session_id_value in _known_session_ids:
		var session_id: int = session_id_value
		var session = get_session(session_id)
		if session != null and session.is_active():
			_active_session_id = session_id
			return session

	return null