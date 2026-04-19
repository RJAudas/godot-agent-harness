@tool
extends EditorPlugin

const ScenegraphDock = preload("res://addons/agent_runtime_harness/editor/scenegraph_dock.gd")
const ScenegraphDebuggerBridge = preload("res://addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd")
const ScenegraphAutomationBroker = preload("res://addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd")
const AgentAssetDeployer = preload("res://addons/agent_runtime_harness/editor/agent_asset_deployer.gd")

var _dock: Control
var _bridge
var _automation_broker: Node
var _agent_asset_deployer: AgentAssetDeployer


func _enter_tree() -> void:
	_bridge = ScenegraphDebuggerBridge.new()
	_bridge.set_session_context({
		"config_path": "res://harness/inspection-run-config.json",
		"requested_by": "editor_plugin",
	})
	add_debugger_plugin(_bridge)

	_automation_broker = ScenegraphAutomationBroker.new()
	_automation_broker.configure(self, _bridge, "res://harness/inspection-run-config.json")
	add_child(_automation_broker)

	_agent_asset_deployer = AgentAssetDeployer.new()

	_dock = ScenegraphDock.new()
	_dock.bind_bridge(_bridge)
	_dock.bind_agent_asset_deployer(_agent_asset_deployer)
	add_control_to_bottom_panel(_dock, "Scenegraph Harness")


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null

	if _automation_broker != null:
		_automation_broker.queue_free()
		_automation_broker = null

	if _bridge != null:
		remove_debugger_plugin(_bridge)
	_bridge = null
	_agent_asset_deployer = null


func _build() -> bool:
	if _automation_broker == null:
		return true
	return _automation_broker.handle_editor_build()
