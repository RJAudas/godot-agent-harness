@tool
extends RefCounted
class_name PlaytestProcessReaper

# B18: reap any leaked playtest godot.exe descendants of the editor before the
# coordinator writes finalStatus=completed. Defensive backstop for cases where
# editor_interface.stop_playing_scene() returns but the OS-level child does not
# exit; previously this leaked a process that blocked the next workflow with
# scene_already_running.
#
# Idempotent — when stop_playing_scene() already worked the helper finds no
# Godot* descendants and returns {"killedPids":[]}.
#
# Synchronous OS.execute on the editor main thread. Typical run is <1s; cold
# pwsh start can push it to ~3s. Acceptable at finalization, where the user is
# already waiting on "run just ended" feedback.

const SCRIPT_RES_PATH := "res://addons/agent_runtime_harness/editor/scripts/Stop-PlaytestChildren.ps1"


static func terminate_playtest_descendants_if_windows() -> Dictionary:
	if OS.get_name() != "Windows":
		return {
			"killedPids": [],
			"survivorPids": [],
			"errors": [],
			"skipped": "non_windows",
			"exitCode": 0,
		}
	var script_path := ProjectSettings.globalize_path(SCRIPT_RES_PATH)
	var editor_pid := OS.get_process_id()
	var args := [
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", script_path,
		"-EditorPid", str(editor_pid),
		"-Json",
	]
	var output: Array = []
	# OS.execute(path, arguments, output, read_stderr, open_console)
	# read_stderr=true so any helper diagnostics surface; open_console=false
	# avoids a console flash on the editor.
	var exit_code := OS.execute("powershell.exe", args, output, true, false)
	var parsed: Dictionary = {
		"killedPids": [],
		"survivorPids": [],
		"errors": [],
		"skipped": null,
	}
	if not output.is_empty():
		var raw := String(output[0]).strip_edges()
		if raw.length() > 0:
			var attempt = JSON.parse_string(raw)
			if typeof(attempt) == TYPE_DICTIONARY:
				parsed["killedPids"] = attempt.get("killedPids", [])
				parsed["survivorPids"] = attempt.get("survivorPids", [])
				parsed["errors"] = attempt.get("errors", [])
				parsed["skipped"] = attempt.get("skipped", null)
	parsed["exitCode"] = exit_code
	return parsed
