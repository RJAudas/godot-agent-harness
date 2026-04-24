@tool
extends RefCounted
class_name AgentAssetDeployer

const TEMPLATE_ROOT := "res://addons/agent_runtime_harness/templates/project_root"
const PROJECT_FILE := "res://project.godot"
const COPILOT_INSTRUCTIONS_FILE := "res://.github/copilot-instructions.md"
const AGENTS_FILE := "res://AGENTS.md"
const PROMPT_FILE := "res://.github/prompts/godot-evidence-triage.prompt.md"
const AGENT_FILE := "res://.github/agents/godot-evidence-triage.agent.md"
const HARNESS_CONFIG_FILE := "res://harness/inspection-run-config.json"
const HARNESS_SOURCE_FILE := "res://harness/harness-source.json"
const HARNESS_REPO_ROOT_TOKEN := "{{HARNESS_REPO_ROOT}}"


func deploy_into_project() -> Dictionary:
	var operations: Array = []
	var errors: Array = []

	if not FileAccess.file_exists(PROJECT_FILE):
		errors.append("project.godot was not found at the project root.")
		return {
			"ok": false,
			"operations": operations,
			"errors": errors,
		}

	_copy_template_tree(".github/prompts", ".github/prompts", operations, errors)
	_copy_template_tree(".github/agents", ".github/agents", operations, errors)
	_copy_claude_skills(operations, errors)
	_ensure_directory("res://evidence/scenegraph/latest", operations)

	var harness_template_path := TEMPLATE_ROOT.path_join("harness/inspection-run-config.json")
	if not FileAccess.file_exists(HARNESS_CONFIG_FILE):
		var harness_result := _copy_template_file(harness_template_path, HARNESS_CONFIG_FILE)
		operations.append(harness_result)
		if harness_result.get("status", "") == "error":
			errors.append(harness_result.get("message", "Failed to create harness config."))
	else:
		operations.append({
			"path": HARNESS_CONFIG_FILE,
			"status": "preserved",
		})

	var copilot_block_result := _install_managed_block(
		COPILOT_INSTRUCTIONS_FILE,
		"AGENT_RUNTIME_HARNESS",
		_read_template(TEMPLATE_ROOT.path_join(".github/copilot-instructions.runtime-harness.md"))
	)
	operations.append(copilot_block_result)
	if copilot_block_result.get("status", "") == "error":
		errors.append(copilot_block_result.get("message", "Failed to write Copilot instructions."))

	var agents_block := _read_template(TEMPLATE_ROOT.path_join("AGENTS.runtime-harness.md"))
	if FileAccess.file_exists(AGENTS_FILE):
		var agents_result := _install_managed_block(AGENTS_FILE, "AGENT_RUNTIME_HARNESS", agents_block)
		operations.append(agents_result)
		if agents_result.get("status", "") == "error":
			errors.append(agents_result.get("message", "Failed to update AGENTS.md."))
	else:
		var agents_content := "# AGENTS.md\n\n<!-- BEGIN AGENT_RUNTIME_HARNESS -->\n%s\n<!-- END AGENT_RUNTIME_HARNESS -->\n" % agents_block.strip_edges()
		var agents_write_result := _write_text(AGENTS_FILE, agents_content)
		operations.append(_build_write_operation(AGENTS_FILE, agents_write_result, "created"))
		if agents_write_result != OK:
			errors.append("Failed to create AGENTS.md.")

	var project_content := _read_text(PROJECT_FILE)
	if project_content == "":
		errors.append("project.godot could not be read.")
	else:
		project_content = _set_ini_property(project_content, "autoload", "ScenegraphHarness", '"*res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd"')
		project_content = _add_packed_string_array_value(project_content, "editor_plugins", "enabled", "res://addons/agent_runtime_harness/plugin.cfg")
		project_content = _set_ini_property(project_content, "harness", "inspection_run_config", '"res://harness/inspection-run-config.json"')
		project_content = _set_ini_property(project_content, "harness", "automation_request_path", '"res://harness/automation/requests/run-request.json"')
		project_content = _set_ini_property(project_content, "harness", "automation_results_directory", '"res://harness/automation/results"')
		var project_write_result := _write_text(PROJECT_FILE, project_content)
		operations.append(_build_write_operation(PROJECT_FILE, project_write_result, "updated"))
		if project_write_result != OK:
			errors.append("Failed to update project.godot.")

	return {
		"ok": errors.is_empty(),
		"operations": operations,
		"errors": errors,
	}


func _copy_template_tree(template_relative_path: String, destination_relative_path: String, operations: Array, errors: Array) -> void:
	var source_directory := TEMPLATE_ROOT.path_join(template_relative_path)
	var source_absolute := ProjectSettings.globalize_path(source_directory)
	var dir := DirAccess.open(source_absolute)
	if dir == null:
		errors.append("Template directory %s could not be opened." % source_directory)
		return

	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry == "":
			break
		if dir.current_is_dir():
			continue

		var source_file := source_directory.path_join(entry)
		var destination_file := "res://%s" % destination_relative_path.path_join(entry)
		var result := _copy_template_file(source_file, destination_file)
		operations.append(result)
		if result.get("status", "") == "error":
			errors.append(result.get("message", "Failed to copy %s." % destination_file))
		
	dir.list_dir_end()


func _copy_claude_skills(operations: Array, errors: Array) -> void:
	var skills_root := TEMPLATE_ROOT.path_join(".claude/skills")
	var skills_absolute := ProjectSettings.globalize_path(skills_root)
	var root_dir := DirAccess.open(skills_absolute)
	if root_dir == null:
		return

	root_dir.list_dir_begin()
	while true:
		var skill_dir_name := root_dir.get_next()
		if skill_dir_name == "":
			break
		if not root_dir.current_is_dir():
			continue
		if skill_dir_name.begins_with("."):
			continue

		var source_skill := skills_root.path_join(skill_dir_name).path_join("SKILL.md")
		var destination_skill := "res://.claude/skills/%s/SKILL.md" % skill_dir_name
		if not FileAccess.file_exists(source_skill):
			continue

		var result := _copy_template_file(source_skill, destination_skill)
		operations.append(result)
		if result.get("status", "") == "error":
			errors.append(result.get("message", "Failed to copy %s." % destination_skill))
	root_dir.list_dir_end()


func _copy_template_file(source_path: String, destination_path: String) -> Dictionary:
	var content := _read_template(source_path)
	if content == "":
		return {
			"path": destination_path,
			"status": "error",
			"message": "Template %s was empty or missing." % source_path,
		}

	var write_result := _write_text(destination_path, content)
	return _build_write_operation(destination_path, write_result, "copied")


func _install_managed_block(path: String, marker_name: String, block_content: String) -> Dictionary:
	var begin_marker := "<!-- BEGIN %s -->" % marker_name
	var end_marker := "<!-- END %s -->" % marker_name
	var managed_block := "%s\n%s\n%s\n" % [begin_marker, block_content.strip_edges(), end_marker]
	var content := _read_text(path)
	var action := "created"

	if content != "":
		var begin_index := content.find(begin_marker)
		var end_index := content.find(end_marker)
		if begin_index >= 0 and end_index > begin_index:
			var suffix_index := end_index + end_marker.length()
			content = "%s%s%s" % [content.substr(0, begin_index), managed_block, content.substr(suffix_index)]
			action = "updated"
		else:
			if not content.ends_with("\n"):
				content += "\n"
			content += managed_block
			action = "appended"
	else:
		content = managed_block

	var write_result := _write_text(path, content)
	return _build_write_operation(path, write_result, action)


func _build_write_operation(path: String, write_result: int, action: String) -> Dictionary:
	if write_result == OK:
		return {
			"path": path,
			"status": action,
		}

	return {
		"path": path,
		"status": "error",
		"message": "Write failed with error %s." % error_string(write_result),
	}


func _get_harness_repo_root() -> String:
	if not FileAccess.file_exists(HARNESS_SOURCE_FILE):
		return ""
	var content := _read_text(HARNESS_SOURCE_FILE)
	if content == "":
		return ""
	var json := JSON.new()
	if json.parse(content) != OK:
		return ""
	var data = json.get_data()
	if data is Dictionary and data.has("harnessRepoRoot"):
		return str(data["harnessRepoRoot"])
	return ""


func _resolve_harness_tokens(content: String) -> String:
	var harness_root := _get_harness_repo_root()
	if harness_root.is_empty():
		return content
	return content.replace(HARNESS_REPO_ROOT_TOKEN, harness_root.replace("\\", "/"))


func _read_template(path: String) -> String:
	return _resolve_harness_tokens(_read_text(path))


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""

	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""

	var content := handle.get_as_text()
	handle.close()
	return content


func _write_text(path: String, content: String) -> int:
	var parent_directory := path.get_base_dir()
	_ensure_directory(parent_directory)

	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return FileAccess.get_open_error()

	handle.store_string(content.strip_edges(false, true) + "\n")
	handle.close()
	return OK


func _ensure_directory(path: String, operations = null) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path)
	if operations is Array:
		operations.append({
			"path": path,
			"status": "ensured-directory",
		})


func _set_ini_property(content: String, section_name: String, key: String, value: String) -> String:
	var lines := content.split("\n")
	var section_header := "[%s]" % section_name
	var section_index := lines.find(section_header)

	if section_index == -1:
		if not lines.is_empty() and lines[lines.size() - 1] != "":
			lines.append("")
		lines.append(section_header)
		lines.append("")
		lines.append("%s=%s" % [key, value])
		return "\n".join(lines).strip_edges(false, true) + "\n"

	var insert_index := lines.size()
	for index in range(section_index + 1, lines.size()):
		if lines[index].begins_with("[") and lines[index].ends_with("]"):
			insert_index = index
			break

	for index in range(section_index + 1, insert_index):
		if lines[index].begins_with("%s=" % key):
			lines[index] = "%s=%s" % [key, value]
			return "\n".join(lines).strip_edges(false, true) + "\n"

	var target_index := section_index + 1
	if target_index < lines.size() and lines[target_index] == "":
		target_index += 1
	lines.insert(target_index, "%s=%s" % [key, value])
	return "\n".join(lines).strip_edges(false, true) + "\n"


func _add_packed_string_array_value(content: String, section_name: String, key: String, value: String) -> String:
	var lines := content.split("\n")
	var section_header := "[%s]" % section_name
	var section_index := lines.find(section_header)

	if section_index == -1:
		return _set_ini_property(content, section_name, key, 'PackedStringArray("%s")' % value)

	var section_end := lines.size()
	for index in range(section_index + 1, lines.size()):
		if lines[index].begins_with("[") and lines[index].ends_with("]"):
			section_end = index
			break

	var regex := RegEx.new()
	regex.compile('"([^"]+)"')

	for index in range(section_index + 1, section_end):
		if not lines[index].begins_with("%s=" % key):
			continue

		var values: Array[String] = []
		for result in regex.search_all(lines[index]):
			values.append(result.get_string(1))

		if value not in values:
			values.append(value)

		var quoted_values: Array[String] = []
		for existing_value in values:
			quoted_values.append('"%s"' % existing_value)

		lines[index] = "%s=PackedStringArray(%s)" % [key, ", ".join(quoted_values)]
		return "\n".join(lines).strip_edges(false, true) + "\n"

	return _set_ini_property(content, section_name, key, 'PackedStringArray("%s")' % value)