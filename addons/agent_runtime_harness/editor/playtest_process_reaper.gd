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
		"parseFailed": false,
	}

	# OS.execute on Windows tends to coalesce all stdout (and merged stderr)
	# into output[0] as one big string with embedded newlines, but the contract
	# is array-of-strings. Iterate every entry, split on newlines, and pick the
	# LAST line that parses to a dict shaped like the helper's payload — that
	# is the JSON Write-Result emits, with any preceding stderr noise discarded.
	var payload: Variant = null
	for entry in output:
		var entry_text := String(entry)
		if entry_text.is_empty():
			continue
		for line in entry_text.split("\n", false):
			var trimmed := String(line).strip_edges()
			if trimmed.is_empty():
				continue
			var attempt = JSON.parse_string(trimmed)
			if typeof(attempt) == TYPE_DICTIONARY and (attempt.has("killedPids") or attempt.has("skipped")):
				payload = attempt

	if payload != null:
		parsed["killedPids"] = payload.get("killedPids", [])
		parsed["survivorPids"] = payload.get("survivorPids", [])
		parsed["errors"] = payload.get("errors", [])
		parsed["skipped"] = payload.get("skipped", null)
	elif not output.is_empty():
		# Output was non-empty but no JSON payload found — surface as a parse
		# failure so the caller can promote terminationStatus rather than
		# silently treating the reap as a clean no-op.
		parsed["parseFailed"] = true
		parsed["errors"] = ["reaper output did not contain expected JSON payload"]

	parsed["exitCode"] = exit_code
	return parsed
