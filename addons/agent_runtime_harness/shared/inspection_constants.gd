@tool
extends RefCounted
class_name InspectionConstants

const EDITOR_TO_RUNTIME_CHANNEL := "agent_runtime_harness/scenegraph/request"
const RUNTIME_TO_EDITOR_CHANNEL := "agent_runtime_harness/scenegraph/capture"

const ARTIFACT_KIND_SCENEGRAPH_SNAPSHOT := "scenegraph-snapshot"
const ARTIFACT_KIND_SCENEGRAPH_DIAGNOSTICS := "scenegraph-diagnostics"
const ARTIFACT_KIND_SCENEGRAPH_SUMMARY := "scenegraph-summary"
const ARTIFACT_KIND_TRACE := "trace"
const ARTIFACT_KIND_AUTOMATION_CAPABILITY := "automation-capability"
const ARTIFACT_KIND_AUTOMATION_LIFECYCLE_STATUS := "automation-lifecycle-status"
const ARTIFACT_KIND_AUTOMATION_RUN_RESULT := "automation-run-result"
const ARTIFACT_KIND_INPUT_DISPATCH_OUTCOMES := "input-dispatch-outcomes"

const DEFAULT_INPUT_DISPATCH_OUTCOMES_FILE := "input-dispatch-outcomes.jsonl"
const DEFAULT_BEHAVIOR_WATCH_TRACE_FILE := "trace.jsonl"

const INPUT_DISPATCH_MAX_EVENTS := 256

const INPUT_DISPATCH_STATUS_DISPATCHED := "dispatched"
const INPUT_DISPATCH_STATUS_SKIPPED_FRAME_UNREACHED := "skipped_frame_unreached"
const INPUT_DISPATCH_STATUS_SKIPPED_RUN_ENDED := "skipped_run_ended"
const INPUT_DISPATCH_STATUS_FAILED := "failed"

const INPUT_DISPATCH_REJECTION_MISSING_FIELD := "missing_field"
const INPUT_DISPATCH_REJECTION_UNSUPPORTED_FIELD := "unsupported_field"
const INPUT_DISPATCH_REJECTION_LATER_SLICE_FIELD := "later_slice_field"
const INPUT_DISPATCH_REJECTION_UNSUPPORTED_IDENTIFIER := "unsupported_identifier"
const INPUT_DISPATCH_REJECTION_UNMATCHED_RELEASE := "unmatched_release"
const INPUT_DISPATCH_REJECTION_SCRIPT_TOO_LONG := "script_too_long"
const INPUT_DISPATCH_REJECTION_INVALID_PHASE := "invalid_phase"
const INPUT_DISPATCH_REJECTION_INVALID_FRAME := "invalid_frame"
const INPUT_DISPATCH_REJECTION_DUPLICATE_EVENT := "duplicate_event"
const INPUT_DISPATCH_REJECTION_INVALID_REQUEST := "invalid_request"
const INPUT_DISPATCH_REJECTION_CAPABILITY_UNSUPPORTED := "capability_unsupported"

const INPUT_DISPATCH_LATER_SLICE_FIELDS := [
	"mouse",
	"touch",
	"gamepad",
	"recordedReplay",
	"physicalKeycode",
	"physicsFrame",
]
const INPUT_DISPATCH_SUPPORTED_REQUEST_KEYS := ["events"]
const INPUT_DISPATCH_SUPPORTED_EVENT_KEYS := ["kind", "identifier", "phase", "frame", "order"]
const INPUT_DISPATCH_SUPPORTED_KINDS := ["key", "action"]
const INPUT_DISPATCH_SUPPORTED_PHASES := ["press", "release"]

const INPUT_DISPATCH_DEBUGGER_KEY_APPLIED := "appliedInputDispatch"
const INPUT_DISPATCH_RUNTIME_KEY_APPLIED := "input_dispatch_script"

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

const AUTOMATION_CONTROL_PATH_FILE_BROKER := "file_broker"
const AUTOMATION_CONTROL_PATH_EDITOR_SCRIPT_FORWARDER := "editor_script_forwarder"
const AUTOMATION_CONTROL_PATH_LOCAL_IPC := "local_ipc"

const AUTOMATION_STATUS_RECEIVED := "received"
const AUTOMATION_STATUS_BLOCKED := "blocked"
const AUTOMATION_STATUS_LAUNCHING := "launching"
const AUTOMATION_STATUS_AWAITING_RUNTIME := "awaiting_runtime"
const AUTOMATION_STATUS_CAPTURING := "capturing"
const AUTOMATION_STATUS_PERSISTING := "persisting"
const AUTOMATION_STATUS_VALIDATING := "validating"
const AUTOMATION_STATUS_STOPPING := "stopping"
const AUTOMATION_STATUS_COMPLETED := "completed"
const AUTOMATION_STATUS_FAILED := "failed"

const AUTOMATION_FAILURE_KIND_LAUNCH := "launch"
const AUTOMATION_FAILURE_KIND_ATTACHMENT := "attachment"
const AUTOMATION_FAILURE_KIND_BUILD := "build"
const AUTOMATION_FAILURE_KIND_CAPTURE := "capture"
const AUTOMATION_FAILURE_KIND_PERSISTENCE := "persistence"
const AUTOMATION_FAILURE_KIND_VALIDATION := "validation"
const AUTOMATION_FAILURE_KIND_SHUTDOWN := "shutdown"
const AUTOMATION_FAILURE_KIND_GAMEPLAY := "gameplay"

const AUTOMATION_BUILD_FAILURE_PHASE_LAUNCHING := "launching"
const AUTOMATION_BUILD_FAILURE_PHASE_AWAITING_RUNTIME := "awaiting_runtime"

const AUTOMATION_TERMINATION_NOT_STARTED := "not_started"
const AUTOMATION_TERMINATION_RUNNING := "running"
const AUTOMATION_TERMINATION_STOPPING := "stopping"
const AUTOMATION_TERMINATION_STOPPED_CLEANLY := "stopped_cleanly"
const AUTOMATION_TERMINATION_ALREADY_CLOSED := "already_closed"
const AUTOMATION_TERMINATION_CRASHED := "crashed"
const AUTOMATION_TERMINATION_SHUTDOWN_FAILED := "shutdown_failed"
const AUTOMATION_TERMINATION_BLOCKED := "blocked"
const AUTOMATION_TERMINATION_UNKNOWN := "unknown"

const DIAGNOSTIC_KIND_MISSING_NODE := "missing_node"
const DIAGNOSTIC_KIND_HIERARCHY_MISMATCH := "hierarchy_mismatch"
const DIAGNOSTIC_KIND_CAPTURE_ERROR := "capture_error"

const BUILD_DIAGNOSTIC_SEVERITY_ERROR := "error"
const BUILD_DIAGNOSTIC_SEVERITY_WARNING := "warning"
const BUILD_DIAGNOSTIC_SEVERITY_UNKNOWN := "unknown"

const BUILD_DIAGNOSTIC_SOURCE_KIND_SCRIPT := "script"
const BUILD_DIAGNOSTIC_SOURCE_KIND_SCENE := "scene"
const BUILD_DIAGNOSTIC_SOURCE_KIND_RESOURCE := "resource"
const BUILD_DIAGNOSTIC_SOURCE_KIND_UNKNOWN := "unknown"

const DEFAULT_SCENARIO_ID := "runtime-smoke-test"
const DEFAULT_OUTPUT_DIRECTORY := "res://evidence/scenegraph/latest"
const DEFAULT_MANIFEST_ARTIFACT_ROOT := ""
const DEFAULT_AUTOMATION_REQUEST_PATH := "res://harness/automation/requests/run-request.json"
const DEFAULT_AUTOMATION_RESULTS_DIRECTORY := "res://harness/automation/results"
const DEFAULT_AUTOMATION_CAPABILITY_RESULT_PATH := "res://harness/automation/results/capability.json"
const DEFAULT_AUTOMATION_LIFECYCLE_STATUS_PATH := "res://harness/automation/results/lifecycle-status.json"
const DEFAULT_AUTOMATION_RUN_RESULT_PATH := "res://harness/automation/results/run-result.json"
const CANONICAL_ISSUE_TRACKER_URL := "https://github.com/RJAudas/godot-agent-harness/issues"


static func supported_artifact_kinds() -> PackedStringArray:
	return PackedStringArray([
		ARTIFACT_KIND_SCENEGRAPH_SNAPSHOT,
		ARTIFACT_KIND_SCENEGRAPH_DIAGNOSTICS,
		ARTIFACT_KIND_SCENEGRAPH_SUMMARY,
		ARTIFACT_KIND_TRACE,
		ARTIFACT_KIND_AUTOMATION_CAPABILITY,
		ARTIFACT_KIND_AUTOMATION_LIFECYCLE_STATUS,
		ARTIFACT_KIND_AUTOMATION_RUN_RESULT,
		ARTIFACT_KIND_INPUT_DISPATCH_OUTCOMES,
	])


static func supported_automation_states() -> PackedStringArray:
	return PackedStringArray([
		AUTOMATION_STATUS_RECEIVED,
		AUTOMATION_STATUS_BLOCKED,
		AUTOMATION_STATUS_LAUNCHING,
		AUTOMATION_STATUS_AWAITING_RUNTIME,
		AUTOMATION_STATUS_CAPTURING,
		AUTOMATION_STATUS_PERSISTING,
		AUTOMATION_STATUS_VALIDATING,
		AUTOMATION_STATUS_STOPPING,
		AUTOMATION_STATUS_COMPLETED,
		AUTOMATION_STATUS_FAILED,
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
