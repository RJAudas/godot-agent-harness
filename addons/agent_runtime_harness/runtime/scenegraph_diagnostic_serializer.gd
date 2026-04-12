extends RefCounted
class_name ScenegraphDiagnosticSerializer

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")
const ScenegraphExpectationEvaluator = preload("res://addons/agent_runtime_harness/runtime/scenegraph_expectation_evaluator.gd")

var _evaluator := ScenegraphExpectationEvaluator.new()


func build_diagnostics(snapshot: Dictionary, expectations: Array) -> Array:
	var diagnostics := _evaluator.evaluate(snapshot, expectations)
	var snapshot_id := String(snapshot.get("snapshot_id", "snapshot"))

	for index in range(diagnostics.size()):
		var diagnostic: Dictionary = diagnostics[index]
		diagnostic["diagnostic_id"] = "%s-diagnostic-%02d" % [snapshot_id, index + 1]
		diagnostic["snapshot_id"] = snapshot_id

	return diagnostics


func build_capture_error(snapshot_id: String, message: String) -> Dictionary:
	return {
		"diagnostic_id": "%s-diagnostic-capture-error" % snapshot_id,
		"snapshot_id": snapshot_id,
		"status": InspectionConstants.DIAGNOSTIC_KIND_CAPTURE_ERROR,
		"message": message,
	}