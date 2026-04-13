@tool
extends Node
class_name ScenegraphAutomationBroker

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphAutomationArtifactStore = preload("res://addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd")
const ScenegraphRunCoordinator = preload("res://addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd")

signal capability_updated(result)
signal run_result_updated(result)

var _plugin: EditorPlugin
var _bridge
var _artifact_store := ScenegraphAutomationArtifactStore.new()
var _run_coordinator := ScenegraphRunCoordinator.new()
var _config_path := "res://harness/inspection-run-config.json"
var _poll_timer: Timer
var _last_capability_signature := ""


func configure(plugin: EditorPlugin, bridge: Object, config_path: String = "res://harness/inspection-run-config.json") -> void:
	_plugin = plugin
	_bridge = bridge
	_config_path = config_path
	_run_coordinator.configure(plugin, bridge, _artifact_store)
	_run_coordinator.run_completed.connect(_on_run_completed)

	if _bridge != null:
		_bridge.session_state_changed.connect(_run_coordinator.handle_session_state_changed)
		_bridge.capture_updated.connect(_run_coordinator.handle_capture_updated)
		_bridge.manifest_persisted.connect(_run_coordinator.handle_manifest_persisted)
		_bridge.transport_error.connect(_run_coordinator.handle_transport_error)

	if _poll_timer == null:
		_poll_timer = Timer.new()
		_poll_timer.wait_time = 0.5
		_poll_timer.one_shot = false
		_poll_timer.autostart = true
		_poll_timer.timeout.connect(_on_poll_timer_timeout)
		add_child(_poll_timer)


func _ready() -> void:
	if _poll_timer != null and _poll_timer.is_stopped():
		_poll_timer.start()


func _on_poll_timer_timeout() -> void:
	var config := _artifact_store.load_harness_config(_config_path)
	if config.is_empty():
		return

	_artifact_store.ensure_automation_layout(config)
	var capability := evaluate_capability(config)
	_publish_capability_if_needed(config, capability)

	if _run_coordinator.is_active():
		_run_coordinator.poll()
		return

	var request := _artifact_store.read_request(config)
	if request.is_empty():
		return

	_artifact_store.clear_request(config)
	_run_coordinator.start_run(config, request, capability, _config_path)


func evaluate_capability(config: Dictionary) -> Dictionary:
	var blocked_reasons: Array = []
	var target_scene := String(config.get("targetScene", ""))
	var harness_autoload := String(ProjectSettings.get_setting("autoload/ScenegraphHarness", ""))
	var launch_control_available := not target_scene.is_empty()
	var runtime_bridge_available := _bridge != null and not harness_autoload.is_empty()
	var capture_control_available := runtime_bridge_available
	var persistence_available := not String(config.get("outputDirectory", "")).is_empty()
	var validation_available := persistence_available
	var shutdown_control_available := true

	if target_scene.is_empty():
		blocked_reasons.append("target_scene_missing")
	if harness_autoload.is_empty():
		blocked_reasons.append("harness_autoload_missing")
	if _run_coordinator.is_active():
		blocked_reasons.append("run_in_progress")
	if _is_playing_scene() and not _run_coordinator.is_active():
		blocked_reasons.append("scene_already_running")
	var deduped_blocked_reasons := _dedupe_strings(blocked_reasons)
	var single_target_ready := deduped_blocked_reasons.is_empty()

	return {
		"checkedAt": InspectionConstants.utc_timestamp_now(),
		"projectIdentifier": ProjectSettings.globalize_path("res://"),
		"singleTargetReady": single_target_ready,
		"launchControlAvailable": launch_control_available,
		"runtimeBridgeAvailable": runtime_bridge_available,
		"captureControlAvailable": capture_control_available,
		"persistenceAvailable": persistence_available,
		"validationAvailable": validation_available,
		"shutdownControlAvailable": shutdown_control_available,
		"blockedReasons": deduped_blocked_reasons,
		"recommendedControlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"notes": [
			"The preferred v1 control surface is the plugin-owned workspace file broker."
		],
	}


func handle_editor_build() -> bool:
	if not _run_coordinator.is_active():
		return true

	var request := _run_coordinator.get_active_request()
	if request.is_empty():
		return true

	var build_failure_phase := InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING
	if _run_coordinator.is_awaiting_runtime():
		build_failure_phase = InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_AWAITING_RUNTIME

	var build_failure := _collect_build_failure_payload(request, build_failure_phase)
	if build_failure.is_empty():
		return true

	_run_coordinator.handle_build_failed(build_failure)
	return false


func _publish_capability_if_needed(config: Dictionary, capability: Dictionary) -> void:
	var signature_payload := capability.duplicate(true)
	signature_payload.erase("checkedAt")
	var signature := JSON.stringify(signature_payload)
	if signature == _last_capability_signature and FileAccess.file_exists(_artifact_store.get_capability_result_path(config)):
		return

	_last_capability_signature = signature
	_artifact_store.write_capability_result(config, capability)
	emit_signal("capability_updated", capability)


func _collect_build_failure_payload(request: Dictionary, build_failure_phase: String) -> Dictionary:
	var target_scene := String(request.get("targetScene", ""))
	if target_scene.is_empty():
		return {}

	var diagnostics := _collect_build_diagnostics(target_scene)
	if diagnostics.is_empty():
		return {}

	var raw_build_output: Array = []
	for diagnostic_value in diagnostics:
		var diagnostic: Dictionary = diagnostic_value
		var raw_excerpt := String(diagnostic.get("rawExcerpt", ""))
		if not raw_excerpt.is_empty():
			raw_build_output.append(raw_excerpt)

	if raw_build_output.is_empty():
		raw_build_output.append("Build validation failed before runtime attachment for %s." % target_scene)

	var details := "Detected %d build diagnostic(s) before runtime attachment." % diagnostics.size()
	return _artifact_store.build_build_failure_payload(build_failure_phase, diagnostics, _dedupe_strings(raw_build_output), details)


func _collect_build_diagnostics(target_scene: String) -> Array:
	var diagnostics: Array = []
	var queued_paths: Array = [target_scene]
	var visited_paths := {}

	while not queued_paths.is_empty():
		var resource_path := String(queued_paths.pop_back())
		if resource_path.is_empty() or visited_paths.has(resource_path):
			continue
		visited_paths[resource_path] = true

		for dependency_ref_value in _resolve_dependency_refs(resource_path):
			var dependency_ref: Dictionary = dependency_ref_value
			var dependency_path := String(dependency_ref.get("resourcePath", ""))
			if dependency_path.is_empty():
				continue
			if not _resource_path_exists(dependency_path):
				diagnostics.append(_build_missing_dependency_diagnostic(dependency_ref))
				continue
			if not visited_paths.has(dependency_path):
				queued_paths.append(dependency_path)

		for diagnostic_value in _inspect_resource_path(resource_path):
			var diagnostic: Dictionary = diagnostic_value
			_append_unique_diagnostic(diagnostics, diagnostic)

	return diagnostics


func _resolve_dependency_refs(resource_path: String) -> Array:
	var dependency_refs: Array = []
	var seen_signatures := {}

	for dependency_value in ResourceLoader.get_dependencies(resource_path):
		var dependency_path := _extract_repo_resource_path(String(dependency_value))
		if dependency_path.is_empty():
			continue
		_append_dependency_ref(dependency_refs, seen_signatures, {
			"resourcePath": dependency_path,
			"line": null,
			"column": null,
			"rawExcerpt": null,
		})

	for parsed_dependency_value in _parse_text_resource_references(resource_path):
		_append_dependency_ref(dependency_refs, seen_signatures, parsed_dependency_value)

	return dependency_refs


func _append_dependency_ref(dependency_refs: Array, seen_signatures: Dictionary, dependency_ref: Dictionary) -> void:
	var resource_path := String(dependency_ref.get("resourcePath", ""))
	if resource_path.is_empty():
		return
	var signature := "%s|%s|%s" % [
		resource_path,
		str(dependency_ref.get("line", null)),
		str(dependency_ref.get("column", null)),
	]
	if seen_signatures.has(signature):
		return
	seen_signatures[signature] = true
	dependency_refs.append({
		"resourcePath": resource_path,
		"line": dependency_ref.get("line", null),
		"column": dependency_ref.get("column", null),
		"rawExcerpt": dependency_ref.get("rawExcerpt", null),
	})


func _parse_text_resource_references(resource_path: String) -> Array:
	if not (resource_path.get_extension().to_lower() in ["tscn", "scn", "tres", "res"]):
		return []
	if not FileAccess.file_exists(resource_path):
		return []

	var handle := FileAccess.open(resource_path, FileAccess.READ)
	if handle == null:
		return []

	var dependency_refs: Array = []
	var line_number := 0
	while not handle.eof_reached():
		line_number += 1
		var raw_line := handle.get_line()
		var search_start := 0
		while true:
			var path_index := raw_line.find("res://", search_start)
			if path_index == -1:
				break
			var resource_text := _extract_resource_path_from_line(raw_line, path_index)
			if not resource_text.is_empty():
				dependency_refs.append({
					"resourcePath": resource_text,
					"line": line_number,
					"column": path_index + 1,
					"rawExcerpt": raw_line.strip_edges(),
				})
			search_start = path_index + 6
	handle.close()
	return dependency_refs


func _extract_resource_path_from_line(raw_line: String, path_index: int) -> String:
	var stop_characters := ["\"", "'", " ", ")", "]", ","]
	var end_index := path_index
	while end_index < raw_line.length():
		var current_character := raw_line.substr(end_index, 1)
		if current_character in stop_characters:
			break
		end_index += 1
	return raw_line.substr(path_index, end_index - path_index).trim_suffix("::")


func _resource_path_exists(resource_path: String) -> bool:
	return ResourceLoader.exists(resource_path) or FileAccess.file_exists(resource_path)


func _build_missing_dependency_diagnostic(dependency_ref: Dictionary) -> Dictionary:
	var resource_path := String(dependency_ref.get("resourcePath", ""))
	var source_kind := _classify_build_source_kind(resource_path)
	var raw_excerpt = dependency_ref.get("rawExcerpt", null)
	var message := "Referenced %s could not be loaded before starting the autonomous run." % source_kind
	if raw_excerpt == null:
		raw_excerpt = "%s: %s" % [resource_path, message]
	return _artifact_store.build_build_diagnostic(
		resource_path,
		message,
		InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
		dependency_ref.get("line", null),
		dependency_ref.get("column", null),
		source_kind,
		"ERR_FILE_NOT_FOUND",
		raw_excerpt
	)


func _append_unique_diagnostic(diagnostics: Array, candidate: Dictionary) -> void:
	if candidate.is_empty():
		return

	for index in range(diagnostics.size()):
		var diagnostic: Dictionary = diagnostics[index]
		if diagnostic.get("resourcePath", null) != candidate.get("resourcePath", null) \
		or diagnostic.get("message", "") != candidate.get("message", "") \
		or diagnostic.get("line", null) != candidate.get("line", null):
			continue

		var existing_column = diagnostic.get("column", null)
		var candidate_column = candidate.get("column", null)
		if existing_column == candidate_column:
			return
		if existing_column == null and candidate_column != null:
			diagnostics[index] = candidate
			return
		if existing_column != null and candidate_column == null:
			return

	diagnostics.append(candidate)


func _extract_repo_resource_path(raw_dependency: String) -> String:
	if raw_dependency.begins_with("res://"):
		return raw_dependency
	for dependency_part in raw_dependency.split("::"):
		if dependency_part.begins_with("res://"):
			return dependency_part
	return ""


func _inspect_resource_path(resource_path: String) -> Array:
	var source_kind := _classify_build_source_kind(resource_path)
	if source_kind == InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT:
		return _inspect_script_resource(resource_path)

	var resource = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource != null:
		return []

	var message := "Failed to load %s before starting the autonomous run." % source_kind
	var raw_excerpt := "%s: %s" % [resource_path, message]
	return [_artifact_store.build_build_diagnostic(
		resource_path,
		message,
		InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
		null,
		null,
		source_kind,
		null,
		raw_excerpt
	)]


func _inspect_script_resource(resource_path: String) -> Array:
	var script: Script = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Script
	if script == null:
		var missing_message := "Failed to load script before starting the autonomous run."
		return [_artifact_store.build_build_diagnostic(
			resource_path,
			missing_message,
			InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
			null,
			null,
			InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT,
			null,
			"%s: %s" % [resource_path, missing_message]
		)]

	var reload_error: int = script.reload(false)
	if reload_error == OK:
		return []

	var editor_diagnostics := _collect_script_editor_diagnostics(resource_path, script)
	if not editor_diagnostics.is_empty():
		return editor_diagnostics

	var message := "Script reload failed with %s." % error_string(reload_error)
	return [_artifact_store.build_build_diagnostic(
		resource_path,
		message,
		InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
		null,
		null,
		InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT,
		null,
		"%s: %s" % [resource_path, message]
	)]


func _collect_script_editor_diagnostics(resource_path: String, script: Script) -> Array:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return []

	var script_editor = editor_interface.get_script_editor()
	if script_editor == null:
		return []

	var previous_script: Script = script_editor.get_current_script()
	editor_interface.edit_script(script, -1, 0, true)
	var current_script: Script = script_editor.get_current_script()
	if current_script == null or current_script.get_path() != resource_path:
		_restore_script_editor(previous_script, resource_path, editor_interface)
		return []
	var current_editor = script_editor.get_current_editor()
	if current_editor == null:
		_restore_script_editor(previous_script, resource_path, editor_interface)
		return []

	var diagnostics: Array = []
	for text_value in _collect_script_editor_text_blocks(current_editor):
		var text := String(text_value)
		for diagnostic_value in _parse_script_editor_diagnostics(resource_path, text):
			var diagnostic: Dictionary = diagnostic_value
			_append_unique_diagnostic(diagnostics, diagnostic)

	_restore_script_editor(previous_script, resource_path, editor_interface)
	return diagnostics


func _restore_script_editor(previous_script: Script, current_resource_path: String, editor_interface) -> void:
	if previous_script == null:
		return
	if previous_script.get_path() == current_resource_path:
		return
	editor_interface.edit_script(previous_script, -1, 0, true)


func _collect_script_editor_text_blocks(root: Node) -> Array:
	var texts: Array = []
	_collect_rich_text_blocks(root, texts)
	return _dedupe_strings(texts)


func _collect_rich_text_blocks(node: Node, texts: Array) -> void:
	if node is RichTextLabel:
		var label: RichTextLabel = node
		var raw_text := label.get_text().strip_edges()
		if not raw_text.is_empty():
			texts.append(raw_text)
		var parsed_text := label.get_parsed_text().strip_edges()
		if not parsed_text.is_empty():
			texts.append(parsed_text)

	for child in node.get_children():
		if child is Node:
			_collect_rich_text_blocks(child, texts)


func _parse_script_editor_diagnostics(default_resource_path: String, text: String) -> Array:
	var diagnostics: Array = []
	var current_resource_path := default_resource_path
	var pending_line = null
	var lines := text.replace("\r", "").split("\n", false)

	for raw_line_value in lines:
		var line_text := String(raw_line_value).strip_edges()
		if line_text.is_empty():
			continue

		var summary_match := _match_script_error_summary(line_text)
		if not summary_match.is_empty():
			diagnostics.append(_artifact_store.build_build_diagnostic(
				current_resource_path,
				String(summary_match.get("message", "")),
				InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
				summary_match.get("line", null),
				summary_match.get("column", null),
				InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT,
				null,
				line_text
			))
			pending_line = null
			continue

		if line_text.begins_with("res://") and line_text.ends_with(":"):
			current_resource_path = line_text.trim_suffix(":")
			pending_line = null
			continue

		var line_match := _match_script_error_line(line_text)
		if not line_match.is_empty():
			var inline_message := String(line_match.get("message", ""))
			if inline_message.is_empty():
				pending_line = {
					"resourcePath": current_resource_path,
					"line": line_match.get("line", null),
				}
				continue

			diagnostics.append(_artifact_store.build_build_diagnostic(
				current_resource_path,
				inline_message,
				InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
				line_match.get("line", null),
				null,
				InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT,
				null,
				line_text
			))
			pending_line = null
			continue

		if pending_line != null:
			diagnostics.append(_artifact_store.build_build_diagnostic(
				String(pending_line.get("resourcePath", current_resource_path)),
				line_text,
				InspectionConstants.BUILD_DIAGNOSTIC_SEVERITY_ERROR,
				pending_line.get("line", null),
				null,
				InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT,
				null,
				"Line %d: %s" % [int(pending_line.get("line", 0)), line_text]
			))
			pending_line = null

	return diagnostics


func _match_script_error_summary(line_text: String) -> Dictionary:
	for pattern in [
		"^Error at \\(\\[hint=Line (\\d+), column (\\d+)\\][^\\]]+\\[/hint\\]\\):\\s*(.+)$",
		"^Error at \\(Line (\\d+), column (\\d+)\\):\\s*(.+)$",
		"^Error at \\((\\d+),\\s*(\\d+)\\):\\s*(.+)$",
	]:
		var regex := RegEx.new()
		if regex.compile(pattern) != OK:
			continue
		var match := regex.search(line_text)
		if match == null:
			continue
		return {
			"line": int(match.get_string(1)),
			"column": int(match.get_string(2)),
			"message": String(match.get_string(3)).strip_edges(),
		}
	return {}


func _match_script_error_line(line_text: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("^Line\\s+(\\d+):\\s*(.*)$") != OK:
		return {}
	var match := regex.search(line_text)
	if match == null:
		return {}
	return {
		"line": int(match.get_string(1)),
		"message": String(match.get_string(2)).strip_edges(),
	}


func _classify_build_source_kind(resource_path: String) -> String:
	var extension := resource_path.get_extension().to_lower()
	if extension == "gd":
		return InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT
	if extension in ["tscn", "scn"]:
		return InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_SCENE
	if extension.is_empty():
		return InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_UNKNOWN
	return InspectionConstants.BUILD_DIAGNOSTIC_SOURCE_KIND_RESOURCE


func _dedupe_strings(values: Array) -> Array:
	var deduped: Array = []
	for value in values:
		var text := String(value)
		if text.is_empty() or text in deduped:
			continue
		deduped.append(text)
	return deduped


func _get_editor_interface():
	if _plugin == null:
		return null
	return _plugin.get_editor_interface()


func _is_playing_scene() -> bool:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return false
	return editor_interface.is_playing_scene()


func _on_run_completed(result: Dictionary) -> void:
	emit_signal("run_result_updated", result)
