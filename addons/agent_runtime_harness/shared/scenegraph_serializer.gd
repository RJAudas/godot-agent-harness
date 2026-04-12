extends RefCounted
class_name ScenegraphSerializer


static func serialize_tree(root_node: Node) -> Array:
	var collected_nodes: Array = []
	_collect_nodes(root_node, collected_nodes)
	collected_nodes.sort_custom(func(a, b):
		return String(a.get("path", "")) < String(b.get("path", ""))
	)
	return collected_nodes


static func serialize_node(node: Node) -> Dictionary:
	var parent_path := ""
	if node.get_parent() != null:
		parent_path = String(node.get_parent().get_path())

	var owner_path := ""
	if node.owner != null:
		owner_path = String(node.owner.get_path())

	var script_class := ""
	var script_value = node.get_script()
	if script_value is Script:
		script_class = script_value.resource_path

	var groups: Array = []
	for group_name in node.get_groups():
		groups.append(String(group_name))

	var entry := {
		"path": String(node.get_path()),
		"type": node.get_class(),
		"parent_path": parent_path,
		"owner_path": owner_path,
		"groups": groups,
		"script_class": script_class,
		"visibility_state": _build_visibility_state(node),
		"processing_state": {
			"process": node.is_processing(),
			"physics_process": node.is_physics_processing(),
		},
		"transform_state": _build_transform_state(node),
		"properties": {
			"name": String(node.name),
			"child_count": node.get_child_count(),
		},
	}

	return entry


static func _collect_nodes(node: Node, collected_nodes: Array) -> void:
	collected_nodes.append(serialize_node(node))
	for child in node.get_children():
		if child is Node:
			_collect_nodes(child, collected_nodes)


static func _build_visibility_state(node: Node) -> Dictionary:
	if node is CanvasItem:
		return {
			"visible": node.visible,
		}

	return {}


static func _build_transform_state(node: Node) -> Dictionary:
	if node is Node2D:
		return {
			"position": [node.position.x, node.position.y],
			"rotation": node.rotation,
			"scale": [node.scale.x, node.scale.y],
		}

	if node is Node3D:
		return {
			"position": [node.position.x, node.position.y, node.position.z],
			"rotation": [node.rotation.x, node.rotation.y, node.rotation.z],
			"scale": [node.scale.x, node.scale.y, node.scale.z],
		}

	return {}