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


func _publish_capability_if_needed(config: Dictionary, capability: Dictionary) -> void:
	var signature_payload := capability.duplicate(true)
	signature_payload.erase("checkedAt")
	var signature := JSON.stringify(signature_payload)
	if signature == _last_capability_signature and FileAccess.file_exists(_artifact_store.get_capability_result_path(config)):
		return

	_last_capability_signature = signature
	_artifact_store.write_capability_result(config, capability)
	emit_signal("capability_updated", capability)


func _dedupe_strings(values: Array) -> Array:
	var deduped: Array = []
	for value in values:
		var text := String(value)
		if text.is_empty() or text in deduped:
			continue
		deduped.append(text)
	return deduped


func _is_playing_scene() -> bool:
	if _plugin == null:
		return false
	var editor_interface = _plugin.get_editor_interface()
	if editor_interface == null:
		return false
	return editor_interface.is_playing_scene()


func _on_run_completed(result: Dictionary) -> void:
	emit_signal("run_result_updated", result)
