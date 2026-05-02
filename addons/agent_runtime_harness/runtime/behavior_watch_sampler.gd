extends RefCounted
class_name BehaviorWatchSampler

var _applied_watch := {}
var _rows: Array = []
var _sampled_frames := {}
var _target_state := {}
var _target_observations := {}


func configure(applied_watch: Dictionary) -> void:
	_applied_watch = applied_watch.duplicate(true)
	_rows.clear()
	_sampled_frames.clear()
	_target_state.clear()
	_target_observations.clear()

	for target_value in _applied_watch.get("targets", []):
		if typeof(target_value) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_value
		var node_path := String(target.get("nodePath", ""))
		if node_path.is_empty():
			continue
		var properties: Array = []
		for property_name_value in target.get("properties", []):
			properties.append(String(property_name_value))
		_target_observations[node_path] = {
			"sampleCount": 0,
			"properties": properties,
			"propertyHits": _build_property_hits(properties),
		}


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
			continue
		_record_target_sample(node_path)
		_rows.append(_build_row_for_target(target_node, target, frame, timestamp_ms))


func get_rows() -> Array:
	return _rows.duplicate(true)


func build_outcomes() -> Dictionary:
	return {
		"sampleCount": _rows.size(),
		"sampledFrameCount": _sampled_frames.size(),
		"noSamples": _rows.is_empty(),
		"missingTargets": _serialize_missing_targets(),
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
				_assign_sampled_property(row, node_path, property_name, position_value, position_value != null)
			"velocity":
				_assign_sampled_property(row, node_path, property_name, velocity_value, velocity_value != null)
			"intendedVelocity":
				_assign_sampled_property(row, node_path, property_name, intended_velocity_value, intended_velocity_value != null)
			"collisionState":
				var collision_available := bool(collision.get("available", false))
				_assign_sampled_property(
					row,
					node_path,
					property_name,
					collision.get("collisionState", null),
					collision_available
				)
			"lastCollider":
				var collider_available := bool(collision.get("available", false))
				_assign_sampled_property(
					row,
					node_path,
					property_name,
					collision.get("lastCollider", null),
					collider_available
				)
			"movementVector":
				_assign_sampled_property(row, node_path, property_name, movement_vector_value, movement_vector_value != null)
			"speed":
				if velocity_value == null:
					_assign_sampled_property(row, node_path, property_name, null, false)
				else:
					_assign_sampled_property(row, node_path, property_name, _vector_length(velocity_value), true)
			"overlapFrames":
				var overlap_available := bool(collision.get("available", false))
				_assign_sampled_property(
					row,
					node_path,
					property_name,
					collision.get("overlapFrames", null),
					overlap_available
				)
			_:
				var generic := _extract_generic_property(node, property_name)
				_assign_sampled_property(
					row,
					node_path,
					property_name,
					generic.get("value", null),
					bool(generic.get("available", false))
				)

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
	return null


func _extract_vector2_property(node: Object, property_names: Array) -> Variant:
	for property_name_value in property_names:
		var property_name := String(property_name_value)
		if not _has_property(node, property_name):
			continue
		var property_value = node.get(property_name)
		if typeof(property_value) == TYPE_VECTOR2:
			return [property_value.x, property_value.y]
		return null
	return null


func _has_property(target: Object, property_name: String) -> bool:
	for property_info in target.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false


func _extract_generic_property(node: Object, property_name: String) -> Dictionary:
	if not _has_property(node, property_name):
		return {"value": null, "available": false}
	var raw_value = node.get(property_name)
	match typeof(raw_value):
		TYPE_BOOL:
			return {"value": bool(raw_value), "available": true}
		TYPE_INT:
			return {"value": int(raw_value), "available": true}
		TYPE_FLOAT:
			return {"value": float(raw_value), "available": true}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"value": String(raw_value), "available": true}
		TYPE_VECTOR2:
			return {"value": [raw_value.x, raw_value.y], "available": true}
		TYPE_VECTOR2I:
			return {"value": [raw_value.x, raw_value.y], "available": true}
		TYPE_COLOR:
			return {"value": [raw_value.r, raw_value.g, raw_value.b, raw_value.a], "available": true}
	return {"value": null, "available": false}


func _vector_length(vector_value: Variant) -> Variant:
	if typeof(vector_value) != TYPE_ARRAY:
		return null
	var values: Array = vector_value
	if values.size() < 2:
		return null
	return sqrt(pow(float(values[0]), 2.0) + pow(float(values[1]), 2.0))


func _assign_sampled_property(
	row: Dictionary,
	node_path: String,
	property_name: String,
	value: Variant,
	sampled: bool
) -> void:
	row[property_name] = value
	if sampled:
		_record_property_hit(node_path, property_name)


func _serialize_missing_properties() -> Array:
	var serialized: Array = []
	var node_paths: Array = _target_observations.keys()
	node_paths.sort()
	for node_path_value in node_paths:
		var node_path := String(node_path_value)
		var observation: Dictionary = _target_observations.get(node_path, {})
		var property_hits: Dictionary = observation.get("propertyHits", {})
		var properties: Array = []
		for property_name_value in observation.get("properties", []):
			var property_name := String(property_name_value)
			if bool(property_hits.get(property_name, false)):
				continue
			properties.append(property_name)
		if properties.is_empty():
			continue
		properties.sort()
		serialized.append({
			"nodePath": node_path,
			"properties": properties,
		})
	return serialized


func _serialize_missing_targets() -> Array:
	var missing_targets: Array = []
	var node_paths: Array = _target_observations.keys()
	node_paths.sort()
	for node_path_value in node_paths:
		var node_path := String(node_path_value)
		var observation: Dictionary = _target_observations.get(node_path, {})
		if int(observation.get("sampleCount", 0)) > 0:
			continue
		missing_targets.append(node_path)
	return missing_targets


func _build_property_hits(properties: Array) -> Dictionary:
	var property_hits := {}
	for property_name_value in properties:
		property_hits[String(property_name_value)] = false
	return property_hits


func _record_target_sample(node_path: String) -> void:
	var observation: Dictionary = _target_observations.get(node_path, {})
	observation["sampleCount"] = int(observation.get("sampleCount", 0)) + 1
	_target_observations[node_path] = observation


func _record_property_hit(node_path: String, property_name: String) -> void:
	var observation: Dictionary = _target_observations.get(node_path, {})
	var property_hits: Dictionary = observation.get("propertyHits", {})
	property_hits[property_name] = true
	observation["propertyHits"] = property_hits
	_target_observations[node_path] = observation


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
