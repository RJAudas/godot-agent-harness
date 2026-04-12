extends RefCounted
class_name ScenegraphSummaryBuilder

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")


func build_summary(snapshot: Dictionary, diagnostics: Array) -> Dictionary:
	var status := "pass"
	var headline := "Scenegraph capture completed successfully."
	var outcome := "Required runtime nodes were present in the latest snapshot."
	var key_findings: Array = []

	if String(snapshot.get("capture_status", "")) == InspectionConstants.CAPTURE_STATUS_ERROR:
		status = "error"
		headline = "Scenegraph capture failed."
		outcome = "The runtime collector could not produce a valid snapshot."
	else:
		for diagnostic_value in diagnostics:
			var diagnostic: Dictionary = diagnostic_value
			if String(diagnostic.get("status", "")) == InspectionConstants.DIAGNOSTIC_KIND_CAPTURE_ERROR:
				status = "error"
				headline = "Scenegraph transport or persistence failed."
				outcome = "A capture error prevented a reliable scenegraph result."
				break
			if String(diagnostic.get("status", "")) in [InspectionConstants.DIAGNOSTIC_KIND_MISSING_NODE, InspectionConstants.DIAGNOSTIC_KIND_HIERARCHY_MISMATCH]:
				status = "fail"
				headline = "Scenegraph diagnostics found missing or misplaced nodes."
				outcome = "The capture succeeded, but one or more required nodes were missing or attached under the wrong branch."

	key_findings.append("Root scene: %s" % String(snapshot.get("root_scene", {}).get("path", "unknown")))
	key_findings.append("Snapshot nodes: %s" % str(snapshot.get("node_count", 0)))
	key_findings.append("Trigger: %s" % String(snapshot.get("trigger", {}).get("trigger_type", InspectionConstants.TRIGGER_MANUAL)))

	for diagnostic_value in diagnostics:
		var diagnostic: Dictionary = diagnostic_value
		key_findings.append("%s: %s" % [String(diagnostic.get("status", "diagnostic")), String(diagnostic.get("message", ""))])

	return {
		"status": status,
		"headline": headline,
		"outcome": outcome,
		"keyFindings": key_findings,
		"latestSnapshotId": String(snapshot.get("snapshot_id", "")),
		"diagnosticCount": diagnostics.size(),
	}