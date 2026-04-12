extends Node
class_name ScenegraphAutoload

const ScenegraphRuntime = preload("res://addons/agent_runtime_harness/runtime/scenegraph_runtime.gd")

var _runtime: ScenegraphRuntime


func _ready() -> void:
	_runtime = ScenegraphRuntime.new()
	_runtime.name = "ScenegraphRuntime"
	add_child(_runtime)
	_runtime.configure_session({
		"config_path": "res://harness/inspection-run-config.json",
		"requested_by": "autoload",
	})


func configure_session(session_context: Dictionary) -> void:
	if _runtime != null:
		_runtime.configure_session(session_context)


func request_capture(trigger_type: String = "manual", reason: String = "manual_request") -> Dictionary:
	if _runtime == null:
		return {}
	return _runtime.capture_scenegraph(trigger_type, reason)


func persist_latest_bundle() -> Dictionary:
	if _runtime == null:
		return {}
	return _runtime.persist_latest_bundle()