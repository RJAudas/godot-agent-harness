# Godot Plugin References

This repository uses a **curated reference** approach instead of copying large sections of the official Godot documentation.

The goal is to give humans and agents the extension points that matter for this project.

## Recommended plugin-first stack

### 1. Editor plugin / addon

Use this for editor UI, controls, docking panels, and debugger integration.

Relevant docs:

- Editor plugins overview  
  https://docs.godotengine.org/en/stable/tutorials/plugins/editor/index.html
- `EditorPlugin` class reference  
  https://docs.godotengine.org/en/stable/classes/class_editorplugin.html

Use for:

- custom dock panels
- toolbar actions
- run controls
- viewing traces and summaries

### 2. Debugger integration

Use this for structured communication between the running game and the editor.

Relevant docs:

- `EditorDebuggerPlugin`  
  https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- `EditorDebuggerSession`  
  https://docs.godotengine.org/en/stable/classes/class_editordebuggersession.html
- `EngineDebugger`  
  https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html

Use for:

- sending trace messages from the game to the editor
- exposing runtime events in a debugger tab
- session-aware debugging data capture

### 3. Runtime addon + autoload singleton

Use this for in-game instrumentation and scenario execution.

Relevant docs:

- Singletons (Autoload)  
  https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
- Nodes and scene tree basics  
  https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html

Use for:

- frame trace collection
- scene tree snapshots
- invariant checks
- event aggregation

### 4. GDExtension

Use only if scripting or plugin APIs are not enough.

Relevant docs:

- What is GDExtension?  
  https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/what_is_gdextension.html
- godot-cpp docs  
  https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/index.html

Use for:

- performance-sensitive telemetry
- lower-level integration not possible in scripts
- native helpers that should not require an engine fork

## Recommended decision rule

Before adding engine-level changes, ask:

1. Can this be implemented as a normal addon?
2. Can this be implemented with editor debugger messaging?
3. Can this be implemented as a GDExtension?
4. Is an engine fork truly required?

If the answer to the first three is "yes" or "probably", do **not** fork the engine yet.

## Local reference checkout

If a local Godot source checkout exists, it should be treated as a **reference repo**, not as part of this repository.

Current local convention relative to the harness repository root:

- `../godot` = Godot source checkout for reading/reference
- `.` = actual harness repository

## What to keep locally in this repo

Keep:

- short implementation notes
- architecture decisions
- links to official docs
- examples specific to this harness

Do not keep:

- copied upstream docs
- large vendored documentation snapshots unless offline use becomes mandatory
