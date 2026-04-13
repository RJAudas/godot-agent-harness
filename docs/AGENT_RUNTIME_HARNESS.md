# Godot Agent Runtime Harness

## Problem

Agent-driven game development is bottlenecked by weak runtime feedback. The current loop is:

1. Agent changes code.
2. Human runs the game.
3. Human describes behavior in natural language.
4. Agent guesses at the fix.

This is especially painful for gameplay bugs such as:

- Ball physics that stick to walls instead of bouncing
- Infinite horizontal bounce loops
- Missing scene instances
- Collision behaviors that appear "wrong" but are hard to describe precisely

The goal of this project is to give agents structured runtime observability so they can debug Godot projects from machine-readable evidence instead of vague human summaries.

## Goal

Build a Godot-compatible runtime harness that exposes enough structured state for agents to:

- run deterministic gameplay scenarios
- inspect the active scene tree / node graph
- read structured logs and event traces
- capture per-frame gameplay telemetry
- evaluate invariants automatically
- detect likely root causes for runtime failures

## Recommended implementation strategy

### Start plugin-first, not engine-fork-first

The first implementation should avoid modifying the Godot engine source directly.

Recommended order:

1. **Editor plugin / addon**
   - Use Godot editor extensibility for UI, controls, and debugger integration.
   - Best for inspector panels, session controls, trace viewing, and export actions.
2. **Runtime addon + autoload singleton**
   - Ship a runtime helper that collects telemetry from the running game.
   - Best for frame traces, event logs, invariant checks, and scenario execution.
3. **Debugger integration**
   - Use `EditorDebuggerPlugin` on the editor side and `EngineDebugger` on the running game side for structured messages between the game and the editor.
4. **GDExtension only if needed**
   - Use GDExtension if scripting-level access is not enough or performance becomes a problem.
5. **Fork the engine only as a last resort**
   - Reserve engine changes for hooks that truly cannot be implemented through addons, debugger integration, or GDExtension.

Implementation and design work should explicitly cite the relevant local docs,
official Godot references, and the reference checkout at `../godot` relative to the
repository root before introducing new abstractions or escalating beyond these
supported layers.

## Why plugin-first is the right next step

Benefits:

- lower maintenance cost than a long-lived engine fork
- easier to iterate on quickly
- easier to keep project-specific
- can live beside game projects instead of inside the engine
- still leaves room to graduate pieces into GDExtension later

Risks avoided:

- rebasing a private engine fork forever
- solving engine-level problems before proving the actual harness design
- coupling the observability system too tightly to one Godot version

## Core requirements

### 1. Deterministic scenario runner

The harness must support reproducible gameplay runs.

Requirements:

- fixed initial conditions
- fixed random seed where applicable
- scripted input playback
- scenario start / stop control
- repeatable run IDs
- headless-friendly execution where possible

Example:

- Run Pong scenario `wall-bounce-left-001`
- Start ball at known position and velocity
- Simulate N frames
- Emit trace and pass/fail result

### 2. Machine-readable frame traces

The harness must emit structured telemetry that agents can read directly.

Preferred output:

- JSON lines or JSON files
- optional CSV export for quick graphing

Per-frame examples:

- frame number
- timestamp
- scene name
- node path
- position
- velocity
- rotation
- collision state
- last collider
- collision normal
- current game state
- score / lives / level

### 3. Scene tree / node graph inspection

The harness must expose the runtime scene tree in a structured form.

Requirements:

- dump active scene tree
- include node names, types, paths, ownership, groups
- include selected property snapshots for important nodes
- detect missing expected instances
- support point-in-time snapshot and post-run snapshot

Primary use cases:

- verifying nodes actually instanced
- identifying missing autoloads
- checking expected hierarchy for gameplay objects
- comparing scene structure before and after a failure

The current editor-first implementation path for scenegraph inspection centers on three persisted artifact kinds:

- `scenegraph-snapshot` for the bounded runtime hierarchy capture
- `scenegraph-diagnostics` for missing-node, hierarchy-mismatch, and capture-error outcomes
- `scenegraph-summary` for the agent-readable entry point that points back to the relevant snapshot and diagnostics

These artifacts are intended to flow through the existing manifest-centered bundle so an agent can read the manifest first, identify the latest scenegraph outcome quickly, and then open only the referenced raw files when deeper inspection is required.

### 4. Structured event and signal logging

The harness must log gameplay-relevant events, not just generic text output.

Examples:

- collision entered / exited
- score changed
- life lost
- state changed from `playing` to `game_over`
- node instantiated / freed
- signal emitted
- scenario checkpoint reached

Requirements:

- event category
- event payload
- source node path
- frame number
- timestamp

### 5. Invariant checks

The harness must support automated assertions over runtime behavior.

Examples:

- ball may not remain overlapping a wall for more than 2 frames
- rally must end in a score within N seconds / frames
- ball speed must remain within configured bounds
- after paddle collision, horizontal velocity must move away from the paddle
- no required gameplay node may be missing after scene startup

Requirements:

- pass/fail result
- human-readable explanation
- machine-readable failure payload
- link to relevant frames/events

### 6. Agent-friendly CLI / run mode

Agents need one stable way to execute the harness.

Requirements:

- run a named scenario
- write outputs to a known directory
- emit concise pass/fail summary
- return non-zero exit code on failed invariants or runtime crashes

Example output contract:

- `trace.jsonl`
- `events.json`
- `scene_tree.json`
- `summary.json`
- `stdout` summary

### 7. Replay and diagnosis support

The harness should make failures replayable and explainable.

Requirements:

- save scenario input
- save seed / config
- save failure window frames
- optionally persist last successful run for diffing

## Suggested architecture

### A. Editor-side plugin

Responsibilities:

- control scenario execution
- receive structured debugger messages
- display traces and failures
- provide export buttons
- show runtime tabs or dock panels

Likely implementation:

- `EditorPlugin`
- `EditorDebuggerPlugin`

The current autonomous editor evidence loop extends this layer with a plugin-owned file broker:

- request artifacts are read from `harness/automation/requests/run-request.json`
- capability, lifecycle, and final result artifacts are written under `harness/automation/results/`
- the broker uses the same plugin-owned path to classify pre-runtime build failures, waits for runtime attachment only when launch succeeds, persists the scenegraph bundle, validates the manifest, and stops the play session when configured to do so

### B. Runtime instrumentation addon

Responsibilities:

- collect telemetry from live nodes
- emit events and frame snapshots
- run invariant checks
- send structured messages back to the editor

Likely implementation:

- addon scripts
- autoload singleton
- lightweight instrumentation helpers attached to tracked nodes

### C. Optional native layer

Responsibilities:

- optimize hot paths
- expose lower-level data if scripting proves insufficient

Likely implementation:

- `GDExtension`

## Evidence bundle handoff

Agents should consume runtime evidence through a manifest-centered bundle instead of opening every raw artifact immediately.

For autonomous editor evidence runs, read the final `harness/automation/results/run-result.json` first:

- if `failureKind = build`, use the build diagnostics and raw build output from that result, surface `details`, `resourcePath`, and `line`/`column` when available, and do not expect a manifest
- otherwise, follow the existing manifest-centered bundle flow

Recommended flow:

1. Read `run-result.json` first for autonomous runs.
2. If the run completed with a manifest, read `evidence-manifest.json`.
3. Use the manifest summary and invariant outcomes to determine pass, fail, or unknown status.
4. Follow `artifactRefs` only for the specific files needed to explain or validate the reported outcome.
5. Preserve the raw artifacts unchanged so later runs can replay, diff, or revalidate the same bundle.

The first-release contract for this repository is captured in `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`.
Seeded examples live under `tools/evals/fixtures/001-agent-tooling-foundation/` and are intended to show the minimum artifact set an agent should expect:

- `summary.json` for normalized outcome and key findings
- `invariants.json` for machine-readable invariant results
- `trace.jsonl` for per-frame evidence
- `events.json` for structured runtime events
- `scene-snapshot.json` for point-in-time hierarchy or state inspection

Agents should treat the autonomous run result as the first routing layer for brokered runs, and treat the manifest as the runtime-evidence routing layer whenever the run actually produced one.

## Non-goals for v1

- full visual understanding from screenshots
- general-purpose AI game playing
- engine-wide invasive instrumentation
- replacing standard gameplay tests

## V1 target

Prove the concept on a small physics-driven game such as Pong.

V1 should answer:

- Did the ball collide with the correct object?
- Did velocity change correctly after collision?
- Did the ball get stuck in contact?
- Did a rally resolve into a score?
- Was the scene tree what we expected?

## Suggested immediate next steps

1. **Do not start by changing the Godot engine itself.**
2. Create a separate repo or workspace for a Godot addon/plugin prototype.
3. Implement a tiny Pong testbed project that uses the harness.
4. Add:
   - deterministic scenario runner
   - frame trace output
   - event logging
   - 3-5 invariants
5. Validate that agents can use the trace artifacts to diagnose a real bug.
6. Only move deeper into GDExtension or an engine fork if a concrete blocker appears.

Each step above should produce machine-readable outputs that an agent can inspect
directly, not only UI state or human-written notes.

## Decision checkpoint

Fork the engine only if at least one of these becomes true:

- Godot scripting APIs cannot expose the required runtime information
- debugger/plugin hooks are insufficient for structured inspection
- performance overhead makes scripting-based telemetry unusable
- the harness requires editor/runtime capabilities only available through engine changes

Until then, prefer addon/plugin + debugger integration.
