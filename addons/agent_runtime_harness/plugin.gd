@tool
extends EditorPlugin

const ScenegraphDock = preload("res://addons/agent_runtime_harness/editor/scenegraph_dock.gd")
const ScenegraphDebuggerBridge = preload("res://addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd")

var _dock: Control
var _bridge


func _enter_tree() -> void:
	_bridge = ScenegraphDebuggerBridge.new()
	_bridge.set_session_context({
		"config_path": "res://harness/inspection-run-config.json"
	})

	_dock = ScenegraphDock.new()
	_dock.bind_bridge(_bridge)
	add_control_to_bottom_panel(_dock, "Scenegraph Harness")


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null

	_bridge = null