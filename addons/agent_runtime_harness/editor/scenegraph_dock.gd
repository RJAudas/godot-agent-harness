@tool
extends VBoxContainer
class_name ScenegraphDock

var _bridge = null
var _status_label: Label
var _summary_label: RichTextLabel
var _diagnostics_label: RichTextLabel
var _capture_button: Button
var _persist_button: Button


func _ready() -> void:
	_build_ui()
	_update_status("Awaiting runtime collector.")


func bind_bridge(bridge: Object) -> void:
	_bridge = bridge
	if _bridge == null:
		return

	if _bridge.has_signal("session_state_changed"):
		_bridge.session_state_changed.connect(_on_session_state_changed)
	if _bridge.has_signal("capture_updated"):
		_bridge.capture_updated.connect(_on_capture_updated)
	if _bridge.has_signal("transport_error"):
		_bridge.transport_error.connect(_on_transport_error)
	if _bridge.has_signal("manifest_persisted"):
		_bridge.manifest_persisted.connect(_on_manifest_persisted)


func _build_ui() -> void:
	if _status_label != null:
		return

	var title := Label.new()
	title.text = "Scenegraph Inspection"
	add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_capture_button = Button.new()
	_capture_button.text = "Capture Snapshot"
	_capture_button.pressed.connect(_on_capture_button_pressed)
	add_child(_capture_button)

	_persist_button = Button.new()
	_persist_button.text = "Persist Bundle"
	_persist_button.pressed.connect(_on_persist_button_pressed)
	add_child(_persist_button)

	var summary_heading := Label.new()
	summary_heading.text = "Latest Snapshot"
	add_child(summary_heading)

	_summary_label = RichTextLabel.new()
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	add_child(_summary_label)

	var diagnostics_heading := Label.new()
	diagnostics_heading.text = "Diagnostics"
	add_child(diagnostics_heading)

	_diagnostics_label = RichTextLabel.new()
	_diagnostics_label.fit_content = true
	_diagnostics_label.scroll_active = false
	add_child(_diagnostics_label)


func _on_capture_button_pressed() -> void:
	if _bridge == null:
		_update_status("No runtime collector is attached.")
		return

	_bridge.request_manual_capture()
	_update_status("Manual capture requested.")


func _on_persist_button_pressed() -> void:
	if _bridge == null:
		_update_status("No runtime collector is attached.")
		return

	_bridge.persist_latest_bundle()
	_update_status("Persist bundle requested.")


func _on_session_state_changed(state: String, details: String) -> void:
	_update_status("%s: %s" % [state.capitalize(), details])


func _on_capture_updated(snapshot: Dictionary, diagnostics: Array) -> void:
	_summary_label.clear()
	_summary_label.append_text(_format_snapshot(snapshot))

	_diagnostics_label.clear()
	_diagnostics_label.append_text(_format_diagnostics(diagnostics))


func _on_transport_error(message: String) -> void:
	_update_status("Transport error: %s" % message)


func _on_manifest_persisted(manifest: Dictionary) -> void:
	_update_status("Persisted manifest %s." % String(manifest.get("manifestId", "unknown")))


func _update_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _format_snapshot(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "No scenegraph snapshot has been captured yet."

	var lines := [
		"Root: %s" % String(snapshot.get("root_scene", {}).get("path", "unknown")),
		"Status: %s" % String(snapshot.get("capture_status", "unknown")),
		"Trigger: %s" % String(snapshot.get("trigger", {}).get("trigger_type", "unknown")),
		"Nodes: %s" % str(snapshot.get("node_count", 0)),
		"Captured At: %s" % String(snapshot.get("captured_at", "unknown")),
	]
	return "\n".join(lines)


func _format_diagnostics(diagnostics: Array) -> String:
	if diagnostics.is_empty():
		return "No missing-node, hierarchy-mismatch, or capture diagnostics were reported."

	var lines: Array = []
	for diagnostic_value in diagnostics:
		var diagnostic: Dictionary = diagnostic_value
		lines.append("[%s] %s" % [String(diagnostic.get("status", "diagnostic")), String(diagnostic.get("message", ""))])
	return "\n".join(lines)