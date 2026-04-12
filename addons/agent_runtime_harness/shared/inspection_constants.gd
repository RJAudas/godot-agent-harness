@tool
extends RefCounted
class_name InspectionConstants

const EDITOR_TO_RUNTIME_CHANNEL := "agent_runtime_harness/scenegraph/request"
const RUNTIME_TO_EDITOR_CHANNEL := "agent_runtime_harness/scenegraph/capture"

const ARTIFACT_KIND_SCENEGRAPH_SNAPSHOT := "scenegraph-snapshot"
const ARTIFACT_KIND_SCENEGRAPH_DIAGNOSTICS := "scenegraph-diagnostics"
const ARTIFACT_KIND_SCENEGRAPH_SUMMARY := "scenegraph-summary"

const TRIGGER_STARTUP := "startup"
const TRIGGER_MANUAL := "manual"
const TRIGGER_FAILURE := "failure"

const CAPTURE_STATUS_COMPLETE := "complete"
const CAPTURE_STATUS_PARTIAL := "partial"
const CAPTURE_STATUS_ERROR := "error"

const SESSION_STATUS_INITIALIZING := "initializing"
const SESSION_STATUS_CONNECTED := "connected"
const SESSION_STATUS_CAPTURING := "capturing"
const SESSION_STATUS_PERSISTED := "persisted"
const SESSION_STATUS_CLOSED := "closed"
const SESSION_STATUS_ERROR := "error"

const DIAGNOSTIC_KIND_MISSING_NODE := "missing_node"
const DIAGNOSTIC_KIND_HIERARCHY_MISMATCH := "hierarchy_mismatch"
const DIAGNOSTIC_KIND_CAPTURE_ERROR := "capture_error"

const DEFAULT_SCENARIO_ID := "runtime-smoke-test"
const DEFAULT_OUTPUT_DIRECTORY := "res://evidence/scenegraph/latest"
const DEFAULT_MANIFEST_ARTIFACT_ROOT := ""


static func supported_artifact_kinds() -> PackedStringArray:
	return PackedStringArray([
		ARTIFACT_KIND_SCENEGRAPH_SNAPSHOT,
		ARTIFACT_KIND_SCENEGRAPH_DIAGNOSTICS,
		ARTIFACT_KIND_SCENEGRAPH_SUMMARY,
	])


static func utc_timestamp_now() -> String:
	var datetime := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		int(datetime.get("year", 1970)),
		int(datetime.get("month", 1)),
		int(datetime.get("day", 1)),
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
		int(datetime.get("second", 0)),
	]