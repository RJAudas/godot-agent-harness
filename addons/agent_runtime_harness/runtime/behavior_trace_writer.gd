extends RefCounted
class_name BehaviorTraceWriter

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")


func persist_trace(rows: Array, session_context: Dictionary) -> Dictionary:
	var output_directory := String(session_context.get("output_directory", InspectionConstants.DEFAULT_OUTPUT_DIRECTORY))
	var artifact_root := String(session_context.get("artifact_root", InspectionConstants.DEFAULT_MANIFEST_ARTIFACT_ROOT))
	if artifact_root.is_empty():
		artifact_root = output_directory.trim_prefix("res://")

	_ensure_directory(output_directory)

	var trace_path := output_directory.path_join(InspectionConstants.DEFAULT_BEHAVIOR_WATCH_TRACE_FILE)
	var temp_path := "%s.%s.tmp" % [trace_path, str(Time.get_ticks_usec())]
	var handle := FileAccess.open(temp_path, FileAccess.WRITE)
	if handle == null:
		return {
			"error": "Could not open %s for writing (%s)." % [trace_path, error_string(FileAccess.get_open_error())],
		}

	for row_value in rows:
		handle.store_string("%s\n" % JSON.stringify(row_value))
	handle.close()

	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_target := ProjectSettings.globalize_path(trace_path)
	if FileAccess.file_exists(trace_path):
		DirAccess.remove_absolute(absolute_target)

	var rename_error := DirAccess.rename_absolute(absolute_temp, absolute_target)
	if rename_error != OK:
		DirAccess.remove_absolute(absolute_temp)
		return {
			"error": "Could not move %s into place (%s)." % [trace_path, error_string(rename_error)],
		}

	return {
		"resourcePath": trace_path,
		"artifactPath": artifact_root.path_join(InspectionConstants.DEFAULT_BEHAVIOR_WATCH_TRACE_FILE),
		"sampleCount": rows.size(),
	}


func _ensure_directory(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
