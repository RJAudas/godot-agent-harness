@tool
extends RefCounted
class_name ScenegraphRunCoordinator

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphAutomationArtifactStore = preload("res://addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd")

signal lifecycle_status_written(payload)
signal run_completed(result)

var _plugin: EditorPlugin
var _bridge
var _artifact_store: ScenegraphAutomationArtifactStore
var _active_config := {}
var _active_request := {}
var _last_manifest := {}
var _last_validation := {}
var _last_build_failure := {}
var _pending_failure_kind: Variant = null
var _pending_failure_message := ""
var _active := false
var _awaiting_runtime := false
var _awaiting_capture := false
var _awaiting_manifest := false
var _awaiting_stop := false
var _stop_requested := false
var _launch_started_at_usec := 0
var _active_config_path := ""


func configure(plugin: EditorPlugin, bridge: Object, artifact_store: ScenegraphAutomationArtifactStore) -> void:
	_plugin = plugin
	_bridge = bridge
	_artifact_store = artifact_store


func is_active() -> bool:
	return _active


func is_awaiting_runtime() -> bool:
	return _awaiting_runtime


func get_active_request() -> Dictionary:
	return _active_request.duplicate(true)


func start_run(config: Dictionary, request: Dictionary, capability: Dictionary, config_path: String = "") -> Dictionary:
	_active_config = config.duplicate(true)
	_active_request = _resolve_request(config, request)
	_active_config_path = config_path
	_last_manifest = {}
	_last_validation = _build_validation_result(false, 0, [], false, ["Validation has not completed yet."])
	_last_build_failure = {}
	_pending_failure_kind = null
	_pending_failure_message = ""
	_stop_requested = false
	_awaiting_stop = false

	var blocked_reasons := _collect_blocked_reasons(capability)
	if not blocked_reasons.is_empty():
		return _finish_blocked_run(blocked_reasons)

	_active = true
	_launch_started_at_usec = Time.get_ticks_usec()
	var request_id := String(_active_request.get("requestId", ""))
	var run_id := String(_active_request.get("runId", ""))
	_emit_status(InspectionConstants.AUTOMATION_STATUS_RECEIVED, "Autonomous run request accepted.")
	_emit_status(InspectionConstants.AUTOMATION_STATUS_LAUNCHING, "Starting the requested scene in the editor.")

	_bridge.set_session_context(_build_session_context())
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		return _finish_blocked_run(["editor_interface_unavailable"])
	editor_interface.play_custom_scene(String(_active_request.get("targetScene", "")))
	if not _active:
		return {
			"ok": false,
			"requestId": request_id,
			"runId": run_id,
		}

	_emit_status(InspectionConstants.AUTOMATION_STATUS_AWAITING_RUNTIME, "Waiting for the runtime debugger session to attach.")
	_awaiting_runtime = true
	_awaiting_capture = true
	_awaiting_manifest = false
	return {
		"ok": true,
		"requestId": request_id,
		"runId": run_id,
	}


func poll() -> void:
	if not _active:
		return

	if _awaiting_runtime:
		var elapsed_usec := Time.get_ticks_usec() - _launch_started_at_usec
		if elapsed_usec > 15000000:
			_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, "Runtime debugger session did not attach before timeout.")
			return

	if _awaiting_stop and not _is_playing_scene():
		_finalize_after_stop(InspectionConstants.AUTOMATION_TERMINATION_STOPPED_CLEANLY)


func handle_session_state_changed(state: String, details: String) -> void:
	if not _active:
		return

	match state:
		InspectionConstants.SESSION_STATUS_CONNECTED:
			_on_runtime_attached()
		"disconnected":
			if _awaiting_stop or _stop_requested:
				_finalize_after_stop(InspectionConstants.AUTOMATION_TERMINATION_STOPPED_CLEANLY)
			elif _awaiting_runtime:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, details)
			elif _last_manifest.is_empty():
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY, "The play session ended before a scenegraph bundle was persisted.")
		InspectionConstants.SESSION_STATUS_ERROR:
			if _awaiting_runtime:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, details)
			elif _awaiting_manifest or _awaiting_capture:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_CAPTURE, details)
			else:
				_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY, details)
		_:
			pass


func handle_capture_updated(snapshot: Dictionary, diagnostics: Array) -> void:
	if not _active or not _awaiting_capture:
		return

	_awaiting_capture = false
	_emit_status(InspectionConstants.AUTOMATION_STATUS_CAPTURING, "Scenegraph evidence capture completed.", {
		"evidenceRefs": _build_snapshot_refs(snapshot, diagnostics),
	})
	_emit_status(InspectionConstants.AUTOMATION_STATUS_PERSISTING, "Persisting the latest scenegraph evidence bundle.")
	_awaiting_manifest = true
	_bridge.persist_latest_bundle()


func handle_manifest_persisted(manifest: Dictionary) -> void:
	if not _active or not _awaiting_manifest:
		return

	_awaiting_manifest = false
	_last_manifest = manifest.duplicate(true)
	_emit_status(InspectionConstants.AUTOMATION_STATUS_VALIDATING, "Validating the persisted evidence bundle.")
	_last_validation = _validate_manifest(manifest)
	if not bool(_last_validation.get("bundleValid", false)):
		_pending_failure_kind = InspectionConstants.AUTOMATION_FAILURE_KIND_VALIDATION
		_pending_failure_message = "Persisted evidence bundle failed validation."

	if _should_stop_after_validation():
		_request_stop()
		return

	if _pending_failure_kind != null:
		_fail_run(String(_pending_failure_kind), _pending_failure_message)
		return

	_finalize_run("completed", null, InspectionConstants.AUTOMATION_TERMINATION_RUNNING)


func handle_transport_error(message: String) -> void:
	if not _active:
		return

	if _awaiting_runtime:
		_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_ATTACHMENT, message)
	elif _awaiting_manifest or _awaiting_capture:
		_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_CAPTURE, message)
	else:
		_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_GAMEPLAY, message)


func handle_build_failed(payload: Dictionary) -> void:
	if not _active:
		return

	_last_build_failure = _artifact_store.normalize_build_failure_payload(payload)
	_awaiting_runtime = false
	_awaiting_capture = false
	_awaiting_manifest = false

	var details := String(_last_build_failure.get("details", "Build diagnostics were detected before runtime attachment."))
	_last_validation = _build_build_failure_validation_result(details)
	_emit_status(
		InspectionConstants.AUTOMATION_STATUS_FAILED,
		details,
		_artifact_store.build_build_failure_status_extras(
			String(_last_build_failure.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING)),
			_last_build_failure.get("buildDiagnostics", []),
			_last_build_failure.get("rawBuildOutput", [])
		)
	)
	_finalize_run("failed", InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD, _derive_build_failure_termination_status(), details, _last_build_failure)


func _on_runtime_attached() -> void:
	_awaiting_runtime = false
	var capture_policy: Dictionary = _active_request.get("capturePolicy", {})
	var startup_enabled := bool(capture_policy.get("startup", false))
	var manual_enabled := bool(capture_policy.get("manual", false))

	if startup_enabled:
		_emit_status(InspectionConstants.AUTOMATION_STATUS_CAPTURING, "Runtime debugger session attached; waiting for startup capture.")
		return

	if manual_enabled:
		_emit_status(InspectionConstants.AUTOMATION_STATUS_CAPTURING, "Runtime debugger session attached; requesting manual capture.")
		_bridge.request_manual_capture()
		return

	_fail_run(InspectionConstants.AUTOMATION_FAILURE_KIND_CAPTURE, "Autonomous capture is disabled by the current capture policy.")


func _request_stop() -> void:
	_stop_requested = true
	_awaiting_stop = true
	_emit_status(InspectionConstants.AUTOMATION_STATUS_STOPPING, "Stopping the editor play session after validation.")
	var editor_interface = _get_editor_interface()
	if editor_interface != null:
		editor_interface.stop_playing_scene()
	if not _is_playing_scene():
		_finalize_after_stop(InspectionConstants.AUTOMATION_TERMINATION_STOPPED_CLEANLY)


func _finalize_after_stop(termination_status: String) -> void:
	_awaiting_stop = false
	if _pending_failure_kind != null:
		_finalize_run("failed", String(_pending_failure_kind), termination_status, _pending_failure_message)
		return

	_finalize_run("completed", null, termination_status)


func _finish_blocked_run(blocked_reasons: Array) -> Dictionary:
	var request_id := String(_active_request.get("requestId", "request-blocked"))
	var run_id := String(_active_request.get("runId", "run-blocked"))
	_emit_status(InspectionConstants.AUTOMATION_STATUS_BLOCKED, "Autonomous run request was blocked.", {
		"evidenceRefs": blocked_reasons,
	})
	var result := {
		"requestId": request_id,
		"runId": run_id,
		"finalStatus": "blocked",
		"failureKind": null,
		"manifestPath": null,
		"outputDirectory": String(_active_request.get("outputDirectory", "")),
		"validationResult": _build_validation_result(false, 0, [], false, ["Run was blocked before evidence validation could begin."]),
		"terminationStatus": InspectionConstants.AUTOMATION_TERMINATION_BLOCKED,
		"blockedReasons": blocked_reasons.duplicate(true),
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"completedAt": InspectionConstants.utc_timestamp_now(),
	}
	_artifact_store.write_run_result(_active_config, result)
	emit_signal("run_completed", result)
	_reset_state()
	return result


func _fail_run(failure_kind: String, message: String) -> void:
	_emit_status(InspectionConstants.AUTOMATION_STATUS_FAILED, message, {
		"failureKind": failure_kind,
	})

	if _should_stop_after_validation() and _is_playing_scene() and not _stop_requested:
		_pending_failure_kind = failure_kind
		_pending_failure_message = message
		_request_stop()
		return

	_finalize_run("failed", failure_kind, _derive_failure_termination_status(), message)


func _finalize_run(final_status: String, failure_kind, termination_status: String, note := "", build_failure := {}) -> void:
	var manifest_path = null
	if not _last_manifest.is_empty():
		manifest_path = _resolve_manifest_repo_path()
	var validation_result := _last_validation.duplicate(true)
	if not note.is_empty():
		var validation_notes: Array = validation_result.get("notes", []).duplicate(true)
		if not note in validation_notes:
			validation_notes.append(note)
		validation_result["notes"] = validation_notes

	var result := {
		"requestId": String(_active_request.get("requestId", "")),
		"runId": String(_active_request.get("runId", "")),
		"finalStatus": final_status,
		"failureKind": failure_kind,
		"manifestPath": manifest_path,
		"outputDirectory": String(_active_request.get("outputDirectory", "")),
		"validationResult": validation_result,
		"terminationStatus": termination_status,
		"blockedReasons": [],
		"controlPath": InspectionConstants.AUTOMATION_CONTROL_PATH_FILE_BROKER,
		"completedAt": InspectionConstants.utc_timestamp_now(),
	}
	if failure_kind == InspectionConstants.AUTOMATION_FAILURE_KIND_BUILD:
		var normalized_build_failure: Dictionary = _artifact_store.normalize_build_failure_payload(build_failure)
		result["buildFailurePhase"] = normalized_build_failure.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING)
		result["buildDiagnostics"] = normalized_build_failure.get("buildDiagnostics", []).duplicate(true)
		result["rawBuildOutput"] = normalized_build_failure.get("rawBuildOutput", []).duplicate(true)
	_artifact_store.write_run_result(_active_config, result)
	emit_signal("run_completed", result)
	_reset_state()


func _emit_status(status: String, details: String, extras := {}) -> void:
	var payload: Dictionary = _artifact_store.build_status_payload(
		String(_active_request.get("requestId", "request-pending")),
		String(_active_request.get("runId", "run-pending")),
		status,
		details,
		extras
	)
	_artifact_store.write_lifecycle_status(_active_config, payload)
	emit_signal("lifecycle_status_written", payload)


func _resolve_active_config_path() -> String:
	if not _active_config_path.is_empty():
		return _active_config_path

	for source in [_active_request, _active_config]:
		var camel_case_path := String(source.get("configPath", ""))
		if not camel_case_path.is_empty():
			return camel_case_path

		var snake_case_path := String(source.get("config_path", ""))
		if not snake_case_path.is_empty():
			return snake_case_path

	return "res://harness/inspection-run-config.json"


func _build_session_context() -> Dictionary:
	return {
		"config_path": _resolve_active_config_path(),
		"session_id": String(_active_request.get("requestId", "")),
		"request_id": String(_active_request.get("requestId", "")),
		"run_id": String(_active_request.get("runId", "")),
		"scenario_id": String(_active_request.get("scenarioId", InspectionConstants.DEFAULT_SCENARIO_ID)),
		"requested_by": String(_active_request.get("requestedBy", "scenegraph_automation_broker")),
		"output_directory": String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY)),
		"artifact_root": String(_active_request.get("artifactRoot", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT)),
		"capture_policy": _active_request.get("capturePolicy", {}).duplicate(true),
		"stop_policy": _active_request.get("stopPolicy", {}).duplicate(true),
	}


func _collect_blocked_reasons(capability: Dictionary) -> Array:
	var blocked: Array = []
	for blocked_reason in capability.get("blockedReasons", []):
		blocked.append(String(blocked_reason))

	if String(_active_request.get("requestId", "")).is_empty():
		blocked.append("request_id_missing")
	if String(_active_request.get("runId", "")).is_empty():
		blocked.append("run_id_missing")
	if String(_active_request.get("targetScene", "")).is_empty():
		blocked.append("target_scene_missing")
	if _is_playing_scene():
		blocked.append("scene_already_running")

	var capture_policy: Dictionary = _active_request.get("capturePolicy", {})
	if not bool(capture_policy.get("startup", false)) and not bool(capture_policy.get("manual", false)):
		blocked.append("capture_policy_blocks_autonomous_capture")

	return _dedupe_strings(blocked)


func _resolve_request(config: Dictionary, request: Dictionary) -> Dictionary:
	var overrides: Dictionary = request.get("overrides", {})
	var default_overrides: Dictionary = config.get("defaultRequestOverrides", {})
	var base_capture_policy: Dictionary = config.get("capturePolicy", {}).duplicate(true)
	var base_stop_policy := {"stopAfterValidation": true}
	var resolved := {
		"requestId": String(request.get("requestId", "request-%s" % str(Time.get_ticks_usec()))),
		"scenarioId": String(request.get("scenarioId", config.get("scenarioId", InspectionConstants.DEFAULT_SCENARIO_ID))),
		"runId": String(request.get("runId", config.get("runId", "run-%s" % str(Time.get_ticks_usec())))),
		"targetScene": String(config.get("targetScene", "")),
		"outputDirectory": String(config.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY)),
		"artifactRoot": String(config.get("artifactRoot", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT)),
		"expectationFiles": _copy_array(config.get("expectationFiles", [])),
		"capturePolicy": base_capture_policy,
		"stopPolicy": base_stop_policy,
		"requestedBy": String(request.get("requestedBy", "scenegraph_automation_broker")),
	}

	_apply_scalar_override(resolved, default_overrides, "targetScene")
	_apply_scalar_override(resolved, default_overrides, "outputDirectory")
	_apply_scalar_override(resolved, default_overrides, "artifactRoot")
	_apply_array_override(resolved, default_overrides, "expectationFiles")
	_merge_nested_override(resolved, "capturePolicy", default_overrides.get("capturePolicy", {}))
	_merge_nested_override(resolved, "stopPolicy", default_overrides.get("stopPolicy", {}))

	_apply_scalar_override(resolved, request, "targetScene")
	_apply_scalar_override(resolved, request, "outputDirectory")
	_apply_scalar_override(resolved, request, "artifactRoot")
	_apply_array_override(resolved, request, "expectationFiles")
	_merge_nested_override(resolved, "capturePolicy", request.get("capturePolicy", {}))
	_merge_nested_override(resolved, "stopPolicy", request.get("stopPolicy", {}))

	_apply_scalar_override(resolved, overrides, "targetScene")
	_apply_scalar_override(resolved, overrides, "outputDirectory")
	_apply_scalar_override(resolved, overrides, "artifactRoot")
	_apply_array_override(resolved, overrides, "expectationFiles")
	_merge_nested_override(resolved, "capturePolicy", overrides.get("capturePolicy", {}))
	_merge_nested_override(resolved, "stopPolicy", overrides.get("stopPolicy", {}))

	return resolved


func _apply_scalar_override(target: Dictionary, source: Dictionary, key: String) -> void:
	if source.has(key):
		target[key] = source.get(key)


func _apply_array_override(target: Dictionary, source: Dictionary, key: String) -> void:
	if source.has(key):
		target[key] = _copy_array(source.get(key, []))


func _merge_nested_override(target: Dictionary, key: String, source: Dictionary) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		return
	var merged: Dictionary = target.get(key, {}).duplicate(true)
	for nested_key in source.keys():
		merged[nested_key] = source[nested_key]
	target[key] = merged


func _copy_array(values: Array) -> Array:
	var copied: Array = []
	for value in values:
		copied.append(value)
	return copied


func _build_validation_result(manifest_exists: bool, artifact_refs_checked: int, missing_artifacts: Array, bundle_valid: bool, notes: Array) -> Dictionary:
	return {
		"manifestExists": manifest_exists,
		"artifactRefsChecked": artifact_refs_checked,
		"missingArtifacts": missing_artifacts.duplicate(true),
		"bundleValid": bundle_valid,
		"notes": notes.duplicate(true),
		"validatedAt": InspectionConstants.utc_timestamp_now(),
	}


func _build_build_failure_validation_result(note: String) -> Dictionary:
	var notes: Array = [
		"No new evidence manifest was produced because the run failed during build before runtime capture.",
	]
	var expected_manifest_path := _resolve_expected_manifest_resource_path()
	if FileAccess.file_exists(expected_manifest_path):
		notes.append("An existing manifest file was ignored so stale evidence would not be reported for this build-failed run.")
	if not note.is_empty():
		notes.append(note)
	return _build_validation_result(false, 0, [], false, notes)


func _validate_manifest(manifest: Dictionary) -> Dictionary:
	if manifest.is_empty():
		return _build_validation_result(false, 0, [], false, ["No manifest was produced for the autonomous run."])

	var missing_artifacts: Array = []
	var notes: Array = []
	var output_directory := String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var artifact_refs: Array = manifest.get("artifactRefs", [])
	for artifact_ref_value in artifact_refs:
		var artifact_ref: Dictionary = artifact_ref_value
		var expected_path := output_directory.path_join(String(artifact_ref.get("path", "")).get_file())
		if not FileAccess.file_exists(expected_path):
			missing_artifacts.append(String(artifact_ref.get("path", "")))

	var run_id_matches := String(manifest.get("runId", "")) == String(_active_request.get("runId", ""))
	var scenario_matches := String(manifest.get("scenarioId", "")) == String(_active_request.get("scenarioId", ""))
	if not run_id_matches:
		notes.append("Manifest runId did not match the active automation request.")
	if not scenario_matches:
		notes.append("Manifest scenarioId did not match the active automation request.")
	if missing_artifacts.is_empty():
		notes.append("Manifest and referenced scenegraph artifacts exist for the active run.")

	var bundle_valid := run_id_matches and scenario_matches and missing_artifacts.is_empty() and bool(manifest.get("validation", {}).get("bundleValid", false))
	return _build_validation_result(true, artifact_refs.size(), missing_artifacts, bundle_valid, notes)


func _build_snapshot_refs(snapshot: Dictionary, diagnostics: Array) -> Array:
	var refs: Array = []
	if not snapshot.is_empty():
		refs.append(String(snapshot.get("snapshot_id", "")))
	if not diagnostics.is_empty():
		refs.append("diagnostics:%d" % diagnostics.size())
	return refs


func _derive_failure_termination_status() -> String:
	if _stop_requested:
		return InspectionConstants.AUTOMATION_TERMINATION_SHUTDOWN_FAILED
	if _is_playing_scene():
		return InspectionConstants.AUTOMATION_TERMINATION_RUNNING
	return InspectionConstants.AUTOMATION_TERMINATION_ALREADY_CLOSED


func _derive_build_failure_termination_status() -> String:
	var build_failure_phase := String(_last_build_failure.get("buildFailurePhase", InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING))
	if _is_playing_scene():
		return InspectionConstants.AUTOMATION_TERMINATION_RUNNING
	if build_failure_phase == InspectionConstants.AUTOMATION_BUILD_FAILURE_PHASE_AWAITING_RUNTIME:
		return InspectionConstants.AUTOMATION_TERMINATION_ALREADY_CLOSED
	return InspectionConstants.AUTOMATION_TERMINATION_NOT_STARTED


func _should_stop_after_validation() -> bool:
	var stop_policy: Dictionary = _active_request.get("stopPolicy", {})
	return bool(stop_policy.get("stopAfterValidation", true))


func _resolve_manifest_repo_path() -> String:
	var artifact_root := String(_active_request.get("artifactRoot", ""))
	if artifact_root.is_empty():
		artifact_root = String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY)).trim_prefix("res://")
	return artifact_root.path_join("evidence-manifest.json")


func _resolve_expected_manifest_resource_path() -> String:
	var output_directory := String(_active_request.get("outputDirectory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	if not output_directory.is_empty():
		return output_directory.path_join("evidence-manifest.json")

	var artifact_root := String(_active_request.get("artifactRoot", ""))
	if artifact_root.begins_with("res://"):
		return artifact_root.path_join("evidence-manifest.json")

	return InspectionConstants.DEFAULT_OUTPUT_DIRECTORY.path_join("evidence-manifest.json")


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


func _reset_state() -> void:
	_active = false
	_awaiting_runtime = false
	_awaiting_capture = false
	_awaiting_manifest = false
	_awaiting_stop = false
	_stop_requested = false
	_pending_failure_kind = null
	_pending_failure_message = ""
	_last_build_failure = {}
	_active_config = {}
	_active_request = {}
	_last_manifest = {}
	_last_validation = {}
	_launch_started_at_usec = 0
	_active_config_path = ""
