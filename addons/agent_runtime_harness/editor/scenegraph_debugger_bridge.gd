@tool
extends EditorDebuggerPlugin
class_name ScenegraphDebuggerBridge

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")

signal session_state_changed(state, details)
signal capture_updated(snapshot, diagnostics)
signal manifest_persisted(manifest)
signal transport_error(message)

var _session_context := {}
var _latest_snapshot := {}
var _latest_diagnostics: Array = []
var _known_session_ids: Array = []
var _active_session_id := -1


func set_session_context(session_context: Dictionary) -> void:
	_session_context = session_context.duplicate(true)
	_configure_active_session()


func _has_capture(capture: String) -> bool:
	return capture == InspectionConstants.RUNTIME_TO_EDITOR_CHANNEL


func _setup_session(session_id: int) -> void:
	if session_id not in _known_session_ids:
		_known_session_ids.append(session_id)

	var session := get_session(session_id)
	if session == null:
		return

	session.started.connect(_on_session_started.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))

	if session.is_active():
		_on_session_started(session_id)


func _capture(message: String, data: Array, session_id: int) -> bool:
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
		"runtime_error":
			if not data.is_empty():
				_on_runtime_error(String(data[0]))
			return true
		_:
			return false


func request_manual_capture() -> void:
	_send_request("request_manual_capture")


func request_failure_capture(reason: String) -> void:
	_send_request("request_failure_capture", [reason])


func persist_latest_bundle() -> void:
	_send_request("persist_latest_bundle")


func get_latest_snapshot() -> Dictionary:
	return _latest_snapshot.duplicate(true)


func get_latest_diagnostics() -> Array:
	return _latest_diagnostics.duplicate(true)


func _on_capture_ready(snapshot: Dictionary, diagnostics: Array) -> void:
	_latest_snapshot = snapshot.duplicate(true)
	_latest_diagnostics = diagnostics.duplicate(true)
	emit_signal("session_state_changed", "capturing", "Scenegraph snapshot received.")
	emit_signal("capture_updated", _latest_snapshot, _latest_diagnostics)


func _on_persistence_completed(manifest: Dictionary) -> void:
	emit_signal("session_state_changed", "persisted", "Scenegraph evidence bundle written.")
	emit_signal("manifest_persisted", manifest)


func _on_runtime_error(message: String) -> void:
	_emit_transport_error(message)


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
	var session := _get_active_session()
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