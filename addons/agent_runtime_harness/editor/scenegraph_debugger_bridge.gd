@tool
extends RefCounted
class_name ScenegraphDebuggerBridge

signal session_state_changed(state, details)
signal capture_updated(snapshot, diagnostics)
signal manifest_persisted(manifest)
signal transport_error(message)

var _runtime = null
var _session_context := {}
var _latest_snapshot := {}
var _latest_diagnostics: Array = []


func set_session_context(session_context: Dictionary) -> void:
	_session_context = session_context.duplicate(true)


func attach_runtime(runtime: Object) -> void:
	_runtime = runtime
	if _runtime == null:
		emit_signal("session_state_changed", "disconnected", "No runtime collector is attached.")
		return

	if _runtime.has_signal("capture_ready"):
		_runtime.capture_ready.connect(_on_capture_ready)
	if _runtime.has_signal("persistence_completed"):
		_runtime.persistence_completed.connect(_on_persistence_completed)
	if _runtime.has_signal("runtime_error"):
		_runtime.runtime_error.connect(_on_runtime_error)
	if _runtime.has_method("configure_session"):
		_runtime.configure_session(_session_context)

	emit_signal("session_state_changed", "connected", "Runtime collector attached.")


func request_manual_capture() -> void:
	if _runtime == null or not _runtime.has_method("request_manual_capture"):
		_emit_transport_error("Manual capture requested before the runtime collector was attached.")
		return
	_runtime.request_manual_capture()


func request_failure_capture(reason: String) -> void:
	if _runtime == null or not _runtime.has_method("request_failure_capture"):
		_emit_transport_error("Failure-triggered capture requested before the runtime collector was attached.")
		return
	_runtime.request_failure_capture(reason)


func persist_latest_bundle() -> void:
	if _runtime == null or not _runtime.has_method("persist_latest_bundle"):
		_emit_transport_error("Persist bundle requested before the runtime collector was attached.")
		return
	_runtime.persist_latest_bundle()


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