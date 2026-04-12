extends RefCounted
class_name ScenegraphCaptureService

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphSerializer = preload("res://addons/agent_runtime_harness/shared/scenegraph_serializer.gd")

var _snapshot_sequence: int = 0


func _build_snapshot_id(session_context: Dictionary, trigger_type: String) -> String:
	_snapshot_sequence += 1
	return "%s-%s-%s-%s" % [
		String(session_context.get("session_id", "session")),
		trigger_type,
		str(Time.get_ticks_usec()),
		str(_snapshot_sequence),
	]


func capture_snapshot(root_node: Node, session_context: Dictionary, trigger_type: String, reason: String) -> Dictionary:
	var timestamp := InspectionConstants.utc_timestamp_now()
	var snapshot_id := _build_snapshot_id(session_context, trigger_type)

	var root_scene := {
		"name": String(root_node.name),
		"path": String(root_node.get_path()),
	}
	var nodes := ScenegraphSerializer.serialize_tree(root_node)

	return {
		"schema_version": "1.0.0",
		"snapshot_id": snapshot_id,
		"session_id": String(session_context.get("session_id", "")),
		"run_id": String(session_context.get("run_id", "")),
		"scenario_id": String(session_context.get("scenario_id", "")),
		"trigger": {
			"trigger_type": trigger_type,
			"requested_by": String(session_context.get("requested_by", "editor_plugin")),
			"reason": reason,
			"frame": Engine.get_process_frames(),
			"timestamp": timestamp,
		},
		"root_scene": root_scene,
		"frame": Engine.get_process_frames(),
		"captured_at": timestamp,
		"node_count": nodes.size(),
		"nodes": nodes,
		"capture_status": InspectionConstants.CAPTURE_STATUS_COMPLETE,
	}