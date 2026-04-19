extends Node
class_name InputDispatchRuntime

signal outcome_recorded(outcome)

const InspectionConstants = preload("res://addons/agent_runtime_harness/shared/inspection_constants.gd")

var _events: Array = []
var _next_event_index := 0
var _run_id := ""
var _start_frame := 0
var _started := false
var _completed := false


func configure(script_dict: Dictionary, run_id: String) -> void:
	_events = script_dict.get("events", []).duplicate(true)
	_run_id = run_id
	_next_event_index = 0
	_completed = false
	_started = false
	set_process(not _events.is_empty())


func _ready() -> void:
	set_process(not _events.is_empty())


func _process(_delta: float) -> void:
	if _completed:
		return
	if _events.is_empty():
		_completed = true
		set_process(false)
		return
	if not _started:
		_start_frame = int(Engine.get_process_frames())
		_started = true

	var current_relative_frame := int(Engine.get_process_frames()) - _start_frame
	while _next_event_index < _events.size():
		var event: Dictionary = _events[_next_event_index]
		var declared_frame := int(event.get("frame", 0))
		if declared_frame > current_relative_frame:
			break
		_dispatch_event(event, declared_frame, current_relative_frame)
		_next_event_index += 1

	if _next_event_index >= _events.size():
		_completed = true
		set_process(false)


func dispatch_remaining_as_skipped(reason_code: String) -> void:
	while _next_event_index < _events.size():
		var event: Dictionary = _events[_next_event_index]
		_emit_outcome(event, int(event.get("frame", 0)), -1, InspectionConstants.INPUT_DISPATCH_STATUS_SKIPPED_RUN_ENDED, reason_code, "Run ended before event could dispatch.")
		_next_event_index += 1
	_completed = true
	set_process(false)


func _dispatch_event(event: Dictionary, declared_frame: int, dispatched_frame: int) -> void:
	var kind := String(event.get("kind", ""))
	var identifier := String(event.get("identifier", ""))
	var phase := String(event.get("phase", ""))
	var pressed := phase == "press"
	var failure_message := ""

	if kind == "key":
		var key_value: Variant = ClassDB.class_get_integer_constant("@GlobalScope", "KEY_%s" % identifier)
		if typeof(key_value) != TYPE_INT or int(key_value) == 0:
			_emit_outcome(event, declared_frame, dispatched_frame, InspectionConstants.INPUT_DISPATCH_STATUS_FAILED, InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_IDENTIFIER, "Key identifier '%s' not resolvable at runtime." % identifier)
			return
		var key_event := InputEventKey.new()
		key_event.keycode = int(key_value)
		key_event.pressed = pressed
		key_event.echo = false
		Input.parse_input_event(key_event)
	elif kind == "action":
		if not InputMap.has_action(identifier):
			_emit_outcome(event, declared_frame, dispatched_frame, InspectionConstants.INPUT_DISPATCH_STATUS_FAILED, InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_IDENTIFIER, "InputMap action '%s' is not declared." % identifier)
			return
		var action_event := InputEventAction.new()
		action_event.action = identifier
		action_event.pressed = pressed
		Input.parse_input_event(action_event)
	else:
		failure_message = "Unsupported input dispatch kind '%s'." % kind
		_emit_outcome(event, declared_frame, dispatched_frame, InspectionConstants.INPUT_DISPATCH_STATUS_FAILED, InspectionConstants.INPUT_DISPATCH_REJECTION_UNSUPPORTED_FIELD, failure_message)
		return

	_emit_outcome(event, declared_frame, dispatched_frame, InspectionConstants.INPUT_DISPATCH_STATUS_DISPATCHED, "", "")


func _emit_outcome(event: Dictionary, declared_frame: int, dispatched_frame: int, status: String, reason_code: String, reason_message: String) -> void:
	var outcome := {
		"runId": _run_id,
		"eventIndex": int(event.get("declaredIndex", _next_event_index)),
		"declaredFrame": declared_frame,
		"dispatchedFrame": dispatched_frame,
		"kind": String(event.get("kind", "")),
		"identifier": String(event.get("identifier", "")),
		"phase": String(event.get("phase", "")),
		"status": status,
	}
	if not reason_code.is_empty():
		outcome["reasonCode"] = reason_code
	if not reason_message.is_empty():
		outcome["reasonMessage"] = reason_message
	emit_signal("outcome_recorded", outcome)
