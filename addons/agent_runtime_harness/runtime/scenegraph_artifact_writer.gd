extends RefCounted
class_name ScenegraphArtifactWriter

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphSummaryBuilder = preload("res://addons/agent_runtime_harness/shared/scenegraph_summary_builder.gd")

var _summary_builder := ScenegraphSummaryBuilder.new()


func persist_bundle(snapshot: Dictionary, diagnostics: Array, session_context: Dictionary) -> Dictionary:
	var output_directory := String(session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var artifact_root := String(session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT))
	var summary := _summary_builder.build_summary(snapshot, diagnostics)

	_ensure_directory(output_directory)

	var snapshot_path := output_directory.path_join("scenegraph-snapshot.json")
	var diagnostics_path := output_directory.path_join("scenegraph-diagnostics.json")
	var summary_path := output_directory.path_join("scenegraph-summary.json")
	var manifest_path := output_directory.path_join("evidence-manifest.json")

	_write_json(snapshot_path, snapshot)
	_write_json(diagnostics_path, {
		"schema_version": "1.0.0",
		"snapshot_id": String(snapshot.get("snapshot_id", "")),
		"session_id": String(session_context.get("session_id", "")),
		"run_id": String(session_context.get("run_id", "")),
		"scenario_id": String(session_context.get("scenario_id", "")),
		"diagnostics": diagnostics,
	})
	_write_json(summary_path, summary)

	var manifest := {
		"schemaVersion": "1.0.0",
		"manifestId": "scenegraph-%s" % String(session_context.get("run_id", snapshot.get("run_id", "unknown-run"))),
		"runId": String(session_context.get("run_id", snapshot.get("run_id", "unknown-run"))),
		"scenarioId": String(session_context.get("scenario_id", snapshot.get("scenario_id", "unknown-scenario"))),
		"status": String(summary.get("status", "unknown")),
		"summary": {
			"headline": String(summary.get("headline", "")),
			"outcome": String(summary.get("outcome", "")),
			"keyFindings": summary.get("keyFindings", []),
		},
		"artifactRefs": [
			_build_artifact_ref(InspectionConstants.ARTIFACT_KIND_SCENEGRAPH_SNAPSHOT, artifact_root, "scenegraph-snapshot.json", "application/json", "Latest scenegraph snapshot for the session."),
			_build_artifact_ref(InspectionConstants.ARTIFACT_KIND_SCENEGRAPH_DIAGNOSTICS, artifact_root, "scenegraph-diagnostics.json", "application/json", "Structured missing-node and hierarchy diagnostics for the session."),
			_build_artifact_ref(InspectionConstants.ARTIFACT_KIND_SCENEGRAPH_SUMMARY, artifact_root, "scenegraph-summary.json", "application/json", "Agent-readable scenegraph summary entry point."),
		],
		"validation": {
			"bundleValid": false,
			"notes": [
				"Validate the persisted bundle with tools/evidence/validate-evidence-manifest.ps1 after the editor run.",
			],
		},
		"createdAt": Time.get_datetime_string_from_system(true),
	}

	_write_json(manifest_path, manifest)
	return {
		"manifest": manifest,
		"output_directory": output_directory,
		"manifest_path": manifest_path,
	}


func _ensure_directory(output_directory: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(output_directory)
	DirAccess.make_dir_recursive_absolute(absolute_path)


func _write_json(path: String, payload: Variant) -> void:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(JSON.stringify(payload, "\t"))
	handle.close()


func _build_artifact_ref(kind: String, artifact_root: String, file_name: String, media_type: String, description: String) -> Dictionary:
	return {
		"kind": kind,
		"path": artifact_root.path_join(file_name),
		"mediaType": media_type,
		"description": description,
	}