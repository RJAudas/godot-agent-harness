extends RefCounted
class_name PauseDecisionRequestValidator
## Validates a parsed pause-decision request dict against the contract defined
## in specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json.
##
## Usage:
##   var result := PauseDecisionRequestValidator.new().validate(request_dict, pause_lookup, decision_log_lookup)
##
## pause_lookup is a Callable(run_id: String, pause_id: int) -> bool that
## returns true if the (runId, pauseId) pair is currently outstanding.
##
## decision_log_lookup is a Callable(run_id: String, pause_id: int) -> bool
## that returns true if a decision record already exists for (runId, pauseId).

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")

const REQUIRED_FIELDS := ["runId", "pauseId", "decision", "submittedBy", "submittedAt"]
const SUPPORTED_FIELDS := ["runId", "pauseId", "decision", "submittedBy", "submittedAt"]
const VALID_DECISIONS := ["continue", "stop"]


func validate(
	request_value: Variant,
	pause_lookup: Callable,
	decision_log_lookup: Callable,
) -> Dictionary:
	if typeof(request_value) != TYPE_DICTIONARY:
		return _reject(
			InspectionConstants.PAUSE_DECISION_REJECTION_MISSING_FIELD,
			"",
			"Pause decision request must be a JSON object.",
		)

	var request: Dictionary = request_value

	# Check for unknown fields first so the agent gets a precise rejection.
	for key in request.keys():
		if String(key) not in SUPPORTED_FIELDS:
			return _reject(
				InspectionConstants.PAUSE_DECISION_REJECTION_UNSUPPORTED_FIELD,
				String(key),
				"Unknown field '%s' in pause decision request." % key,
			)

	# Check required fields.
	for field in REQUIRED_FIELDS:
		if not request.has(field):
			return _reject(
				InspectionConstants.PAUSE_DECISION_REJECTION_MISSING_FIELD,
				field,
				"Required field '%s' is missing from pause decision request." % field,
			)

	# Validate decision enum.
	var decision := String(request.get("decision", ""))
	if decision not in VALID_DECISIONS:
		return _reject(
			InspectionConstants.PAUSE_DECISION_REJECTION_INVALID_DECISION,
			"decision",
			"Invalid decision value '%s'; expected one of: %s." % [decision, ", ".join(VALID_DECISIONS)],
		)

	var run_id := String(request.get("runId", ""))
	var pause_id: int = int(request.get("pauseId", -1))

	# Check if the pause is outstanding.
	if not pause_lookup.call(run_id, pause_id):
		return _reject(
			InspectionConstants.PAUSE_DECISION_REJECTION_UNKNOWN_PAUSE,
			"pauseId",
			"No outstanding pause with runId='%s' pauseId=%d." % [run_id, pause_id],
		)

	# Check if a decision was already recorded.
	if decision_log_lookup.call(run_id, pause_id):
		return _reject(
			InspectionConstants.PAUSE_DECISION_REJECTION_DECISION_ALREADY_RECORDED,
			"pauseId",
			"A decision has already been recorded for runId='%s' pauseId=%d." % [run_id, pause_id],
		)

	return {
		"ok": true,
		"code": "",
		"field": "",
		"message": "",
		"runId": run_id,
		"pauseId": pause_id,
		"decision": decision,
		"submittedBy": String(request.get("submittedBy", "")),
		"submittedAt": String(request.get("submittedAt", "")),
	}


func _reject(code: String, field: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"field": field,
		"message": message,
	}
