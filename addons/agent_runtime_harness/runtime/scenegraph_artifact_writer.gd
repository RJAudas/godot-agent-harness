extends RefCounted
class_name ScenegraphArtifactWriter

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphSummaryBuilder = preload("res://addons/agent_runtime_harness/shared/scenegraph_summary_builder.gd")

var _summary_builder := ScenegraphSummaryBuilder.new()


func persist_bundle(snapshot: Dictionary, diagnostics: Array, session_context: Dictionary) -> Dictionary:
	var output_directory := String(session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var artifact_root := _resolve_artifact_root(session_context, output_directory)
	var summary := _summary_builder.build_summary(snapshot, diagnostics)
	var behavior_watch: Dictionary = session_context.get("behavior_watch", {})
	var applied_watch: Dictionary = behavior_watch.get("appliedWatch", {})
	var applied_input_dispatch: Dictionary = session_context.get("applied_input_dispatch", {})
	var run_id := String(session_context.get("run_id", snapshot.get("run_id", "unknown-run")))
	var validation_notes: Array = [
		"Persisted artifact references were written successfully. Validate the manifest schema and paths with tools/evidence/validate-evidence-manifest.ps1 after the editor run.",
	]
	if not applied_watch.is_empty():
		var key_findings: Array = summary.get("keyFindings", []).duplicate(true)
		var watch_outcomes: Dictionary = applied_watch.get("outcomes", {})
		key_findings.append("Behavior watch samples: %d" % int(watch_outcomes.get("sampleCount", 0)))
		summary["keyFindings"] = key_findings

	_ensure_directory(output_directory)

	var snapshot_path := output_directory.path_join("scenegraph-snapshot.json")
	var diagnostics_path := output_directory.path_join("scenegraph-diagnostics.json")
	var summary_path := output_directory.path_join("scenegraph-summary.json")
	var manifest_path := output_directory.path_join("evidence-manifest.json")

	var snapshot_error := _write_json(snapshot_path, snapshot)
	if not snapshot_error.is_empty():
		return {"error": snapshot_error}

	var diagnostics_error := _write_json(diagnostics_path, {
		"schema_version": "1.0.0",
		"snapshot_id": String(snapshot.get("snapshot_id", "")),
		"session_id": String(session_context.get("session_id", "")),
		"run_id": run_id,
		"scenario_id": String(session_context.get("scenario_id", "")),
		"diagnostics": diagnostics,
	})
	if not diagnostics_error.is_empty():
		return {"error": diagnostics_error}

	var summary_error := _write_json(summary_path, summary)
	if not summary_error.is_empty():
		return {"error": summary_error}

	var bundle_valid := _has_persisted_bundle(snapshot_path, diagnostics_path, summary_path)
	var artifact_refs: Array = [
		_build_artifact_ref(InspectionConstants.ARTIFACT_KIND_SCENEGRAPH_SNAPSHOT, artifact_root, "scenegraph-snapshot.json", "application/json", "Latest scenegraph snapshot for the session."),
		_build_artifact_ref(InspectionConstants.ARTIFACT_KIND_SCENEGRAPH_DIAGNOSTICS, artifact_root, "scenegraph-diagnostics.json", "application/json", "Structured missing-node and hierarchy diagnostics for the session."),
		_build_artifact_ref(InspectionConstants.ARTIFACT_KIND_SCENEGRAPH_SUMMARY, artifact_root, "scenegraph-summary.json", "application/json", "Agent-readable scenegraph summary entry point."),
	]

	if not applied_watch.is_empty():
		var trace_file_name := String(applied_watch.get("traceArtifact", InspectionConstants.DEFAULT_BEHAVIOR_WATCH_TRACE_FILE)).get_file()
		var trace_path := output_directory.path_join(trace_file_name)
		artifact_refs.append(_build_artifact_ref(
			InspectionConstants.ARTIFACT_KIND_TRACE,
			artifact_root,
			trace_file_name,
			"application/jsonl",
			"Bounded behavior-watch trace for the current automation run."
		))
		bundle_valid = bundle_valid and FileAccess.file_exists(trace_path)

		var watch_outcomes: Dictionary = applied_watch.get("outcomes", {})
		if bool(watch_outcomes.get("noSamples", false)):
			validation_notes.append("Behavior watch completed without producing any trace rows for the configured window.")
		var missing_targets: Array = watch_outcomes.get("missingTargets", [])
		if not missing_targets.is_empty():
			validation_notes.append("Behavior watch did not resolve requested targets: %s." % _join_strings(missing_targets))
		var missing_properties: Array = watch_outcomes.get("missingProperties", [])
		for missing_property_value in missing_properties:
			var missing_property: Dictionary = missing_property_value
			validation_notes.append(
				"Behavior watch could not sample %s from %s." % [
					_join_strings(missing_property.get("properties", [])),
					String(missing_property.get("nodePath", "")),
				]
			)
		if not FileAccess.file_exists(trace_path):
			validation_notes.append("Behavior watch trace artifact was requested but trace.jsonl was not written.")

	if not applied_input_dispatch.is_empty():
		var input_dispatch_validation := _validate_input_dispatch_outcomes(_input_dispatch_outcomes_path(output_directory), run_id)
		bundle_valid = bundle_valid and bool(input_dispatch_validation.get("bundleValid", false))
		for note_value in input_dispatch_validation.get("notes", []):
			validation_notes.append(String(note_value))
		if bool(input_dispatch_validation.get("includeArtifact", false)):
			artifact_refs.append(_build_artifact_ref(
				InspectionConstants.ARTIFACT_KIND_INPUT_DISPATCH_OUTCOMES,
				artifact_root,
				InspectionConstants.DEFAULT_INPUT_DISPATCH_OUTCOMES_FILE,
				"application/jsonl",
				"Per-event runtime input-dispatch outcomes captured during the run."
			))

	# ---------------------------------------------------------------------------
	# T016: Runtime error records (feature 007)
	# ---------------------------------------------------------------------------
	var runtime_error_records: Array = session_context.get("runtime_error_records", [])
	var runtime_error_reporting := {}
	var runtime_error_records_path := output_directory.path_join(InspectionConstants.DEFAULT_RUNTIME_ERROR_RECORDS_FILE)
	var flush_result := _flush_runtime_error_records(runtime_error_records, runtime_error_records_path, run_id)
	# B10: emit the runtime-error-records artifactRef unconditionally — even when
	# the flush itself failed — so consumers always have a stable path to inspect
	# (an absent artifact is indistinguishable from a broken pipeline; an empty or
	# error-stamped file is unambiguously "no errors" or "flush failed, see notes").
	# Always ensure the referenced file exists; on flush success with an empty
	# dedup map, _flush_runtime_error_records is a no-op so we touch the file here.
	# On flush error, _flush_runtime_error_records may have produced a partial
	# write; touch is idempotent and the validation note carries the failure cause.
	_ensure_runtime_error_records_empty(runtime_error_records_path)
	artifact_refs.append(_build_artifact_ref(
		InspectionConstants.ARTIFACT_KIND_RUNTIME_ERROR_RECORDS,
		artifact_root,
		InspectionConstants.DEFAULT_RUNTIME_ERROR_RECORDS_FILE,
		"application/jsonl",
		"Deduplicated runtime error and warning records captured after the runtime harness attaches."
	))
	runtime_error_reporting["runtimeErrorRecordsArtifact"] = artifact_root.path_join(InspectionConstants.DEFAULT_RUNTIME_ERROR_RECORDS_FILE)
	if flush_result.has("error"):
		validation_notes.append("Runtime error records could not be flushed: %s" % String(flush_result.get("error", "")))
		# A flush failure is a hard evidence-integrity issue; mark the bundle
		# invalid so consumers don't trust the records artifact silently.
		bundle_valid = false
	# T034: pauseOnErrorMode is set from the session context (coordinator stamps it at run start).
	var pause_on_error_mode := String(session_context.get("pause_on_error_mode", InspectionConstants.PAUSE_ON_ERROR_MODE_ACTIVE))
	runtime_error_reporting["pauseOnErrorMode"] = pause_on_error_mode if not pause_on_error_mode.is_empty() else InspectionConstants.PAUSE_ON_ERROR_MODE_ACTIVE

	# T031: termination is set by the coordinator via set_termination message before persist.
	var termination := String(session_context.get("termination", InspectionConstants.RUNTIME_TERMINATION_COMPLETED))
	if termination.is_empty():
		termination = InspectionConstants.RUNTIME_TERMINATION_COMPLETED
	runtime_error_reporting["termination"] = termination

	# T031: Add lastErrorAnchor only when termination = crashed.
	if termination == InspectionConstants.RUNTIME_TERMINATION_CRASHED:
		var last_error_anchor: Variant = session_context.get("last_error_anchor", null)
		if last_error_anchor != null and typeof(last_error_anchor) == TYPE_DICTIONARY and not (last_error_anchor as Dictionary).is_empty():
			runtime_error_reporting["lastErrorAnchor"] = (last_error_anchor as Dictionary).duplicate(true)
		else:
			runtime_error_reporting["lastErrorAnchor"] = {"lastError": "none"}

	# ---------------------------------------------------------------------------
	# T026: Pause decision log (feature 007)
	# ---------------------------------------------------------------------------
	var pause_decision_log: Array = session_context.get("pause_decision_log", [])
	var pause_decision_log_path := output_directory.path_join(InspectionConstants.DEFAULT_PAUSE_DECISION_LOG_FILE)
	var pdl_flush_result := _flush_pause_decision_log(pause_decision_log, pause_decision_log_path, run_id)
	if pdl_flush_result.has("error"):
		validation_notes.append("Pause decision log could not be flushed: %s" % String(pdl_flush_result.get("error", "")))
	else:
		if not pause_decision_log.is_empty():
			artifact_refs.append(_build_artifact_ref(
				InspectionConstants.ARTIFACT_KIND_PAUSE_DECISION_LOG,
				artifact_root,
				InspectionConstants.DEFAULT_PAUSE_DECISION_LOG_FILE,
				"application/jsonl",
				"One row per resolved pause: (runId, pauseId, cause, decision, decisionSource, latencyMs)."
			))
			runtime_error_reporting["pauseDecisionLogArtifact"] = artifact_root.path_join(InspectionConstants.DEFAULT_PAUSE_DECISION_LOG_FILE)

	var manifest := {
		"schemaVersion": "1.0.0",
		"manifestId": "scenegraph-%s" % run_id,
		"runId": run_id,
		"scenarioId": String(session_context.get("scenario_id", snapshot.get("scenario_id", "unknown-scenario"))),
		"status": String(summary.get("status", "unknown")),
		"summary": {
			"headline": String(summary.get("headline", "")),
			"outcome": String(summary.get("outcome", "")),
			"keyFindings": summary.get("keyFindings", []),
		},
		"artifactRefs": artifact_refs,
		"runtimeErrorReporting": runtime_error_reporting,
		"validation": {
			"bundleValid": bundle_valid,
			"notes": validation_notes,
		},
		"producer": _build_producer(session_context),
		"createdAt": InspectionConstants.utc_timestamp_now(),
	}
	if not applied_watch.is_empty():
		manifest["appliedWatch"] = applied_watch.duplicate(true)
	if not applied_input_dispatch.is_empty():
		manifest["appliedInputDispatch"] = applied_input_dispatch.duplicate(true)

	var manifest_error := _write_json(manifest_path, manifest)
	if not manifest_error.is_empty():
		return {"error": manifest_error}

	return {
		"manifest": manifest,
		"output_directory": output_directory,
		"manifest_path": manifest_path,
	}


func reset_input_dispatch_outcomes(session_context: Dictionary) -> String:
	var applied_input_dispatch: Dictionary = session_context.get("applied_input_dispatch", {})
	if applied_input_dispatch.is_empty():
		return ""

	var output_directory := String(session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	_ensure_directory(output_directory)
	var outcomes_path := _input_dispatch_outcomes_path(output_directory)
	if not FileAccess.file_exists(outcomes_path):
		return ""

	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(outcomes_path))
	if remove_error != OK:
		return "Could not clear %s before starting input dispatch (%s)." % [outcomes_path, error_string(remove_error)]
	return ""


func append_input_dispatch_outcome(session_context: Dictionary, outcome: Dictionary) -> String:
	var output_directory := String(session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var expected_run_id := String(session_context.get("run_id", ""))
	var outcome_run_id := String(outcome.get("runId", ""))
	if not expected_run_id.is_empty() and outcome_run_id != expected_run_id:
		return "Refused to append input dispatch outcome for run '%s' into run '%s' output." % [outcome_run_id, expected_run_id]

	_ensure_directory(output_directory)
	var path := _input_dispatch_outcomes_path(output_directory)
	var handle: FileAccess
	if FileAccess.file_exists(path):
		handle = FileAccess.open(path, FileAccess.READ_WRITE)
		if handle != null:
			handle.seek_end()
	else:
		handle = FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return "Could not open %s for input dispatch outcome append (%s)." % [path, error_string(FileAccess.get_open_error())]
	handle.store_line(JSON.stringify(outcome))
	handle.close()
	return ""


func _ensure_directory(output_directory: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(output_directory)
	DirAccess.make_dir_recursive_absolute(absolute_path)


func _write_json(path: String, payload: Variant) -> String:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return "Could not open %s for writing (%s)." % [path, error_string(FileAccess.get_open_error())]

	handle.store_string(JSON.stringify(payload, "\t"))
	handle.close()
	return ""


func _has_persisted_bundle(snapshot_path: String, diagnostics_path: String, summary_path: String) -> bool:
	return FileAccess.file_exists(snapshot_path) \
		and FileAccess.file_exists(diagnostics_path) \
		and FileAccess.file_exists(summary_path)


func _resolve_artifact_root(session_context: Dictionary, output_directory: String) -> String:
	var configured_root := String(session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT))
	if not configured_root.is_empty():
		return configured_root
	return output_directory.trim_prefix("res://")


func _build_artifact_ref(kind: String, artifact_root: String, file_name: String, media_type: String, description: String) -> Dictionary:
	return {
		"kind": kind,
		"path": artifact_root.path_join(file_name),
		"mediaType": media_type,
		"description": description,
	}


func _build_producer(session_context: Dictionary) -> Dictionary:
	var producer := {
		"surface": "scenegraph_harness_runtime",
	}
	var request_id := String(session_context.get("request_id", ""))
	if not request_id.is_empty():
		producer["toolingArtifactId"] = "scenegraph_automation_broker"
	return producer


func _input_dispatch_outcomes_path(output_directory: String) -> String:
	return output_directory.path_join(InspectionConstants.DEFAULT_INPUT_DISPATCH_OUTCOMES_FILE)


func _validate_input_dispatch_outcomes(outcomes_path: String, run_id: String) -> Dictionary:
	if not FileAccess.file_exists(outcomes_path):
		return {
			"includeArtifact": false,
			"bundleValid": false,
			"notes": ["Input dispatch was requested but input-dispatch-outcomes.jsonl was not written."],
		}

	var handle := FileAccess.open(outcomes_path, FileAccess.READ)
	if handle == null:
		return {
			"includeArtifact": false,
			"bundleValid": false,
			"notes": ["Input dispatch outcomes could not be opened for validation."],
		}

	var row_count := 0
	var notes: Array = []
	while not handle.eof_reached():
		var raw_line := handle.get_line().strip_edges()
		if raw_line.is_empty():
			continue
		row_count += 1
		var parsed := JSON.parse_string(raw_line)
		if typeof(parsed) != TYPE_DICTIONARY:
			handle.close()
			return {
				"includeArtifact": false,
				"bundleValid": false,
				"notes": ["Input dispatch outcomes contained a non-object JSONL row."],
			}
		var outcome_row: Dictionary = parsed
		if String(outcome_row.get("runId", "")) != run_id:
			handle.close()
			return {
				"includeArtifact": false,
				"bundleValid": false,
				"notes": ["Input dispatch outcomes contained rows from a different runId."],
			}
	handle.close()

	if row_count <= 0:
		notes.append("Input dispatch outcomes file was present but contained no rows.")
		return {
			"includeArtifact": false,
			"bundleValid": false,
			"notes": notes,
		}

	notes.append("Input dispatch outcomes were validated for the active run.")
	return {
		"includeArtifact": true,
		"bundleValid": true,
		"notes": notes,
	}


func _join_strings(values: Array) -> String:
	var parts: Array = []
	for value in values:
		parts.append(String(value))
	return ", ".join(parts)


func _flush_runtime_error_records(records: Array, path: String, run_id: String) -> Dictionary:
	## Write runtime-error-records.jsonl; one row per dedup key.
	## Returns {} on success or { "error": <message> } on failure.
	if records.is_empty():
		return {}

	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return {"error": "Could not open %s for writing (%s)." % [path, error_string(FileAccess.get_open_error())]}

	for record_value in records:
		var record: Dictionary = record_value
		# Safety: enforce run_id consistency.
		record["runId"] = run_id
		handle.store_line(JSON.stringify(record))

	handle.close()
	return {}


func _ensure_runtime_error_records_empty(path: String) -> void:
	## Write an empty JSONL file so the path exists for manifest references.
	if FileAccess.file_exists(path):
		return
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle != null:
		handle.close()


func _flush_pause_decision_log(log: Array, path: String, run_id: String) -> Dictionary:
	## Write pause-decision-log.jsonl; one row per resolved pause, ordered by pauseId.
	if log.is_empty():
		return {}

	var sorted_log := log.duplicate(true)
	sorted_log.sort_custom(func(a, b): return int(a.get("pauseId", 0)) < int(b.get("pauseId", 0)))

	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return {"error": "Could not open %s for writing (%s)." % [path, error_string(FileAccess.get_open_error())]}

	for entry_value in sorted_log:
		var entry: Dictionary = entry_value
		entry["runId"] = run_id
		handle.store_line(JSON.stringify(entry))

	handle.close()
	return {}
