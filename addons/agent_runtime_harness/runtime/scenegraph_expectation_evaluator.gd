extends RefCounted
class_name ScenegraphExpectationEvaluator

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")


func evaluate(snapshot: Dictionary, expectations: Array) -> Array:
	var diagnostics: Array = []
	var nodes: Array = snapshot.get("nodes", [])

	for expectation_value in expectations:
		var expectation: Dictionary = expectation_value
		var match_result := _find_match(nodes, expectation)
		var expectation_id := String(expectation.get("expectation_id", "unnamed-expectation"))

		if not match_result.get("found", false):
			if expectation.get("required", true):
				diagnostics.append({
					"expectation_id": expectation_id,
					"status": InspectionConstants.DIAGNOSTIC_KIND_MISSING_NODE,
					"message": String(expectation.get("failure_message", "Required node was not found in the scenegraph snapshot.")),
					"expected_identity": _describe_expectation(expectation),
				})
			continue

		var matched_node: Dictionary = match_result.get("node", {})
		var mismatch_fields: Array = []

		var required_parent := String(expectation.get("required_parent", ""))
		if not required_parent.is_empty() and String(matched_node.get("parent_path", "")) != required_parent:
			mismatch_fields.append("parent_path")

		var required_properties: Dictionary = expectation.get("required_properties", {})
		for property_name in required_properties.keys():
			var actual_value = _resolve_required_property(matched_node, String(property_name))
			if actual_value != required_properties[property_name]:
				mismatch_fields.append(String(property_name))

		if mismatch_fields.is_empty():
			continue

		diagnostics.append({
			"expectation_id": expectation_id,
			"status": InspectionConstants.DIAGNOSTIC_KIND_HIERARCHY_MISMATCH,
			"message": "Matched node did not satisfy the expected hierarchy or identity requirements.",
			"observed_path": String(matched_node.get("path", "")),
			"expected_parent": required_parent,
			"mismatch_fields": mismatch_fields,
		})

	return diagnostics


func _find_match(nodes: Array, expectation: Dictionary) -> Dictionary:
	var exact_path := String(expectation.get("exact_path", ""))
	if not exact_path.is_empty():
		for node_value in nodes:
			var node: Dictionary = node_value
			if String(node.get("path", "")) == exact_path:
				return {
					"found": true,
					"node": node,
				}

	var selectors: Array = expectation.get("selectors", [])
	if selectors.is_empty():
		return {"found": false}

	var matching_nodes: Array = []
	for node_value in nodes:
		var node: Dictionary = node_value
		if _matches_selectors(node, selectors):
			matching_nodes.append(node)

	if matching_nodes.is_empty():
		return {"found": false}

	matching_nodes.sort_custom(func(a, b):
		return String(a.get("path", "")) < String(b.get("path", ""))
	)
	return {
		"found": true,
		"node": matching_nodes[0],
	}


func _matches_selectors(node: Dictionary, selectors: Array) -> bool:
	for selector_value in selectors:
		var selector: Dictionary = selector_value
		if not _selector_matches(node, selector):
			return false
	return true


func _selector_matches(node: Dictionary, selector: Dictionary) -> bool:
	var selector_type := String(selector.get("selector_type", ""))
	var expected_value := selector.get("value")
	match selector_type:
		"name":
			return String(node.get("properties", {}).get("name", "")) == String(expected_value)
		"group":
			return expected_value in node.get("groups", [])
		"type":
			return String(node.get("type", "")) == String(expected_value)
		"script_class":
			return String(node.get("script_class", "")) == String(expected_value)
		_:
			return false


func _resolve_required_property(node: Dictionary, property_name: String):
	if property_name == "groups":
		return node.get("groups", [])
	if property_name == "script_class":
		return String(node.get("script_class", ""))
	return node.get("properties", {}).get(property_name)


func _describe_expectation(expectation: Dictionary) -> String:
	var exact_path := String(expectation.get("exact_path", ""))
	if not exact_path.is_empty():
		return exact_path

	var selectors: Array = expectation.get("selectors", [])
	var selector_parts: Array = []
	for selector_value in selectors:
		var selector: Dictionary = selector_value
		selector_parts.append("%s=%s" % [selector.get("selector_type", "unknown"), selector.get("value", "")])
	return ", ".join(selector_parts)