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

# ---------------------------------------------------------------------------
# Runtime error reporting (feature 007)
# ---------------------------------------------------------------------------

## Artifact kinds for the two new JSONL artifacts
const ARTIFACT_KIND_RUNTIME_ERROR_RECORDS := "runtime-error-records"
const ARTIFACT_KIND_PAUSE_DECISION_LOG := "pause-decision-log"

## Default filenames
const DEFAULT_RUNTIME_ERROR_RECORDS_FILE := "runtime-error-records.jsonl"
const DEFAULT_PAUSE_DECISION_LOG_FILE := "pause-decision-log.jsonl"
const DEFAULT_LAST_ERROR_ANCHOR_FILE := "last-error-anchor.json"

## Per-key dedup repeat cap
const RUNTIME_ERROR_REPEAT_CAP := 100

## Runtime error severities
const RUNTIME_ERROR_SEVERITY_ERROR := "error"
const RUNTIME_ERROR_SEVERITY_WARNING := "warning"

## Pause causes (why the run paused)
const PAUSE_CAUSE_RUNTIME_ERROR := "runtime_error"
const PAUSE_CAUSE_UNHANDLED_EXCEPTION := "unhandled_exception"
const PAUSE_CAUSE_USER_BREAKPOINT := "paused_at_user_breakpoint"

## Pause decisions (what was decided)
const PAUSE_DECISION_CONTINUED := "continued"
const PAUSE_DECISION_STOPPED := "stopped"
const PAUSE_DECISION_TIMEOUT_DEFAULT_APPLIED := "timeout_default_applied"
const PAUSE_DECISION_STOPPED_BY_DISCONNECT := "stopped_by_disconnect"
const PAUSE_DECISION_RESOLVED_BY_RUN_END := "resolved_by_run_end"

## Pause decision sources (who/what made the decision)
const PAUSE_DECISION_SOURCE_AGENT := "agent"
const PAUSE_DECISION_SOURCE_TIMEOUT_DEFAULT := "timeout_default"
const PAUSE_DECISION_SOURCE_DISCONNECT := "disconnect"
const PAUSE_DECISION_SOURCE_RUN_END := "run_end"

## Run termination kinds (how the run ended overall)
const RUNTIME_TERMINATION_COMPLETED := "completed"
const RUNTIME_TERMINATION_STOPPED_BY_AGENT := "stopped_by_agent"
const RUNTIME_TERMINATION_STOPPED_BY_DEFAULT_ON_PAUSE_TIMEOUT := "stopped_by_default_on_pause_timeout"
const RUNTIME_TERMINATION_CRASHED := "crashed"
const RUNTIME_TERMINATION_KILLED_BY_HARNESS := "killed_by_harness"

## Pause-on-error mode (is pause active or degraded to capture-only)
const PAUSE_ON_ERROR_MODE_ACTIVE := "active"
const PAUSE_ON_ERROR_MODE_UNAVAILABLE_DEGRADED_CAPTURE_ONLY := "unavailable_degraded_capture_only"

## Pause-decision request rejection codes
const PAUSE_DECISION_REJECTION_MISSING_FIELD := "missing_field"
const PAUSE_DECISION_REJECTION_UNSUPPORTED_FIELD := "unsupported_field"
const PAUSE_DECISION_REJECTION_INVALID_DECISION := "invalid_decision"
const PAUSE_DECISION_REJECTION_UNKNOWN_PAUSE := "unknown_pause"
const PAUSE_DECISION_REJECTION_DECISION_ALREADY_RECORDED := "decision_already_recorded"

## Debugger message names for the runtime-error-reporting channel
const RUNTIME_ERROR_MSG_RECORD := "runtime_error_record"
const RUNTIME_ERROR_MSG_PAUSE := "runtime_pause"
const RUNTIME_ERROR_MSG_PAUSE_DECISION := "pause_decision"
const RUNTIME_ERROR_MSG_PAUSE_DECISION_ACK := "pause_decision_ack"
const RUNTIME_ERROR_MSG_PAUSE_DECISION_LOG := "pause_decision_log"
const RUNTIME_ERROR_MSG_SET_TERMINATION := "set_termination"
## T034: sent by coordinator at session start to configure degraded mode.
const RUNTIME_ERROR_MSG_SET_PAUSE_ON_ERROR_MODE := "set_pause_on_error_mode"

## Default pause-decision timeout in seconds
const PAUSE_DECISION_TIMEOUT_SECONDS := 30
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
