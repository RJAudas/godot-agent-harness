extends RefCounted
class_name BehaviorWatchSampler

var _applied_watch := {}
var _rows: Array = []
var _missing_targets: Array = []
var _missing_properties := {}
var _sampled_frames := {}
var _target_state := {}


func configure(applied_watch: Dictionary) -> void:
	_applied_watch = applied_watch.duplicate(true)
	_rows.clear()
	_missing_targets.clear()
	_missing_properties.clear()
	_sampled_frames.clear()
	_target_state.clear()


func is_enabled() -> bool:
	return not _applied_watch.is_empty() and not _applied_watch.get("targets", []).is_empty()


func capture_frame(context_node: Node, frame: int, timestamp_ms: int) -> void:
	if not is_enabled():
		return
	if _is_before_window(frame) or _is_after_window(frame):
		return
	if not _should_sample_frame(frame):
		return

	_sampled_frames[str(frame)] = true
	var targets: Array = _applied_watch.get("targets", [])
	for target_value in targets:
		var target: Dictionary = target_value
		var node_path := String(target.get("nodePath", ""))
		var target_node := context_node.get_node_or_null(NodePath(node_path))
		if target_node == null:
			if not node_path in _missing_targets:
				_missing_targets.append(node_path)
			continue
		_rows.append(_build_row_for_target(target_node, target, frame, timestamp_ms))


func get_rows() -> Array:
	return _rows.duplicate(true)


func build_outcomes() -> Dictionary:
	return {
		"sampleCount": _rows.size(),
		"sampledFrameCount": _sampled_frames.size(),
		"noSamples": _rows.is_empty(),
		"missingTargets": _missing_targets.duplicate(true),
		"missingProperties": _serialize_missing_properties(),
	}


func _build_row_for_target(node: Node, target: Dictionary, frame: int, timestamp_ms: int) -> Dictionary:
	var node_path := String(target.get("nodePath", ""))
	var row := {
		"frame": frame,
		"timestampMs": timestamp_ms,
		"nodePath": node_path,
	}
	var target_state: Dictionary = _target_state.get(node_path, {
		"lastCollider": "",
		"overlapFrames": 0,
	})
	var collision := _build_collision_observation(node, target_state)
	_target_state[node_path] = collision.get("state", target_state)

	var velocity_value = _extract_vector2_property(node, ["velocity"])
	var intended_velocity_value = _extract_vector2_property(node, ["intended_velocity", "intendedVelocity"])
	var movement_vector_value = _extract_vector2_property(node, ["movement_vector", "movementVector"])
	if movement_vector_value == null:
		movement_vector_value = velocity_value

	for property_name_value in target.get("properties", []):
		var property_name := String(property_name_value)
		match property_name:
			"position":
				var position_value = _extract_position(node)
				row[property_name] = position_value
				if position_value == null:
					_record_missing_property(node_path, property_name)
			"velocity":
				row[property_name] = velocity_value
				if velocity_value == null:
					_record_missing_property(node_path, property_name)
			"intendedVelocity":
				row[property_name] = intended_velocity_value
				if intended_velocity_value == null:
					_record_missing_property(node_path, property_name)
			"collisionState":
				row[property_name] = collision.get("collisionState", null)
				if not bool(collision.get("available", false)):
					_record_missing_property(node_path, property_name)
			"lastCollider":
				row[property_name] = collision.get("lastCollider", null)
				if not bool(collision.get("available", false)):
					_record_missing_property(node_path, property_name)
			"movementVector":
				row[property_name] = movement_vector_value
				if movement_vector_value == null:
					_record_missing_property(node_path, property_name)
			"speed":
				if velocity_value == null:
					row[property_name] = null
					_record_missing_property(node_path, property_name)
				else:
					row[property_name] = _vector_length(velocity_value)
			"overlapFrames":
				row[property_name] = collision.get("overlapFrames", null)
				if not bool(collision.get("available", false)):
					_record_missing_property(node_path, property_name)

	return row


func _build_collision_observation(node: Node, target_state: Dictionary) -> Dictionary:
	if not node.has_method("get_slide_collision_count"):
		return {
			"available": false,
			"collisionState": null,
			"lastCollider": null,
			"overlapFrames": null,
			"state": target_state.duplicate(true),
		}

	var collision_count := int(node.call("get_slide_collision_count"))
	var collision_state := "none"
	var last_collider: Variant = null
	var overlap_frames := 0
	var next_state: Dictionary = target_state.duplicate(true)

	if collision_count > 0:
		collision_state = "contact"
		if node.has_method("get_last_slide_collision"):
			var collision = node.call("get_last_slide_collision")
			last_collider = _extract_collider_identity(collision)
		if last_collider != null and String(last_collider) == String(target_state.get("lastCollider", "")):
			overlap_frames = int(target_state.get("overlapFrames", 0)) + 1
		else:
			overlap_frames = 1

	next_state["lastCollider"] = String(last_collider) if last_collider != null else ""
	next_state["overlapFrames"] = overlap_frames
	return {
		"available": true,
		"collisionState": collision_state,
		"lastCollider": last_collider,
		"overlapFrames": overlap_frames,
		"state": next_state,
	}


func _extract_collider_identity(collision) -> Variant:
	if collision == null:
		return null
	if not collision.has_method("get_collider"):
		return null

	var collider = collision.call("get_collider")
	if collider is Node:
		return String(collider.get_path())
	if collider == null:
		return null
	return String(collider)


func _extract_position(node: Node) -> Variant:
	if node is Node2D:
		return [node.position.x, node.position.y]
	if node is Node3D:
		return [node.position.x, node.position.y, node.position.z]
	return null


func _extract_vector2_property(node: Object, property_names: Array) -> Variant:
	for property_name_value in property_names:
		var property_name := String(property_name_value)
		if not _has_property(node, property_name):
			continue
		var property_value = node.get(property_name)
		if typeof(property_value) == TYPE_VECTOR2:
			return [property_value.x, property_value.y]
		if typeof(property_value) == TYPE_VECTOR3:
			return [property_value.x, property_value.y, property_value.z]
		return null
	return null


func _has_property(target: Object, property_name: String) -> bool:
	for property_info in target.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false


func _vector_length(vector_value: Variant) -> Variant:
	if typeof(vector_value) != TYPE_ARRAY:
		return null
	var values: Array = vector_value
	if values.size() < 2:
		return null
	return sqrt(pow(float(values[0]), 2.0) + pow(float(values[1]), 2.0))


func _record_missing_property(node_path: String, property_name: String) -> void:
	var properties: Array = _missing_properties.get(node_path, [])
	if property_name in properties:
		return
	properties.append(property_name)
	_missing_properties[node_path] = properties


func _serialize_missing_properties() -> Array:
	var serialized: Array = []
	var node_paths: Array = _missing_properties.keys()
	node_paths.sort()
	for node_path_value in node_paths:
		var node_path := String(node_path_value)
		var properties: Array = _missing_properties.get(node_path, []).duplicate(true)
		properties.sort()
		serialized.append({
			"nodePath": node_path,
			"properties": properties,
		})
	return serialized


func _is_before_window(frame: int) -> bool:
	return frame < int(_applied_watch.get("startFrameOffset", 0))


func _is_after_window(frame: int) -> bool:
	return frame >= _window_end_frame()


func _window_end_frame() -> int:
	return int(_applied_watch.get("startFrameOffset", 0)) + int(_applied_watch.get("frameCount", 0))


func _should_sample_frame(frame: int) -> bool:
	var start_frame := int(_applied_watch.get("startFrameOffset", 0))
	var cadence: Dictionary = _applied_watch.get("cadence", {})
	var mode := String(cadence.get("mode", "every_frame"))
	if mode != "every_n_frames":
		return true
	var every_n_frames := int(cadence.get("everyNFrames", 1))
	if every_n_frames <= 1:
		return true
	return ((frame - start_frame) % every_n_frames) == 0
