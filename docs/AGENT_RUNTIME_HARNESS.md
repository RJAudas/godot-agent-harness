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
- the broker starts the requested target scene, waits for runtime attachment, persists the scenegraph bundle, validates the manifest, and stops the play session when configured to do so

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

Recommended flow:

1. Read `evidence-manifest.json` first.
2. Use the manifest summary and invariant outcomes to determine pass, fail, or unknown status.
3. Follow `artifactRefs` only for the specific files needed to explain or validate the reported outcome.
4. Preserve the raw artifacts unchanged so later runs can replay, diff, or revalidate the same bundle.

The first-release contract for this repository is captured in `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`.
Seeded examples live under `tools/evals/fixtures/001-agent-tooling-foundation/` and are intended to show the minimum artifact set an agent should expect:

- `summary.json` for normalized outcome and key findings
- `invariants.json` for machine-readable invariant results
- `trace.jsonl` for per-frame evidence
- `events.json` for structured runtime events
- `scene-snapshot.json` for point-in-time hierarchy or state inspection

Agents should treat the manifest as the routing layer and raw files as supporting evidence, not the other way around.

## Runtime input dispatch

Agents can drive a small, deterministic keyboard/input-action script through the running game by attaching an `inputDispatchScript` to the existing automation run request. The harness validates the script before launch, dispatches each accepted event through Godot's real `Input.parse_input_event()` pipeline at the declared process frame, and persists one row per declared event to a fixed `input-dispatch-outcomes.jsonl` artifact registered in the run's evidence manifest.

Recommended flow:

1. Check the editor capability for an `inputDispatch` entry (`pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot <project>`); a `supported: false` value or a non-empty `blockedReasons` array means the feature is unavailable on the current editor and the agent must stop, not improvise.
2. Add a run-scoped `inputDispatchScript` (or place it under `overrides.inputDispatchScript`) on the request. Each event declares `kind` (`key` or `action`), `identifier` (logical `Key` enum suffix such as `KP_ENTER`, or a declared `InputMap` action), `phase` (`press` or `release`), and a non-negative `frame`. The script accepts at most 256 events.
3. Submit the request through the existing automation helper (`pwsh ./tools/automation/request-editor-evidence-run.ps1 ...`).
4. Read the run result first, then the persisted evidence manifest. The manifest references `input-dispatch-outcomes.jsonl`; each row carries the declared frame, the dispatched frame (or `-1` if skipped), and a fixed status enum (`dispatched`, `skipped_frame_unreached`, `skipped_run_ended`, `failed`).

Rejections are machine-readable and surface before the playtest launches. Documented codes include `script_too_long`, `unsupported_identifier`, `unmatched_release`, `later_slice_field`, `invalid_phase`, `invalid_frame`, `duplicate_event`, `missing_field`, `unsupported_field`, and `capability_unsupported`. The authoritative contract lives in `specs/006-input-dispatch/contracts/`, with seeded fixtures under `tools/tests/fixtures/pong-testbed/harness/automation/requests/input-dispatch/` and the end-to-end walkthrough in `specs/006-input-dispatch/quickstart.md`.

Slice 1 intentionally excludes mouse, touch, gamepad, recorded replay, physical keycodes, and physics-frame anchoring; requests that include those fields are rejected with `later_slice_field` so agents can reason about feature scope from the rejection itself.

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

## Runtime error reporting and pause-on-error

Feature `specs/007-report-runtime-errors` adds structured runtime error capture, pause-on-error control, and crash classification to every evidence bundle.

### New artifacts in the bundle

| Artifact kind | File | Description |
|---|---|---|
| `runtime-error-records` | `runtime-error-records.jsonl` | One JSONL row per deduplicated error or warning. Keyed by `(scriptPath, line, severity)`. `repeatCount` is capped at 100 (`truncatedAt` set when cap is hit). Ordered by `firstSeenAt` ASC. |
| `pause-decision-log` | `pause-decision-log.jsonl` | One JSONL row per pause resolution event. Empty when the run completed without any errors or when the environment is in degraded mode. |

### `runtimeErrorReporting` manifest block

Every run manifest now carries a `runtimeErrorReporting` block:

```json
{
  "runtimeErrorReporting": {
    "termination": "completed",
    "pauseOnErrorMode": "active",
    "runtimeErrorRecordsArtifact": "evidence/automation/<runId>/runtime-error-records.jsonl",
    "pauseDecisionLogArtifact": "evidence/automation/<runId>/pause-decision-log.jsonl"
  }
}
```

`termination` values:
- `completed` — clean shutdown handshake received.
- `stopped_by_agent` — agent sent a `stop` decision via `submit-pause-decision.ps1`.
- `stopped_by_default_on_pause_timeout` — 30-second pause timeout applied `stop` automatically.
- `crashed` — process exited without a handshake. `lastErrorAnchor` is populated (or `{ "lastError": "none" }` if no error was seen before the crash).
- `killed_by_harness` — coordinator stopped the run for internal limit reasons.

`pauseOnErrorMode` values:
- `active` — pause-on-error is available; the harness will pause the playtest and wait for an agent decision.
- `unavailable_degraded_capture_only` — the environment cannot support debug-pause; errors are captured but no pause is raised.

### Pause-on-error decision flow

1. Runtime captures an `error`-severity event → raises engine debug-pause and emits a `runtime_pause` message.
2. Editor coordinator suspends input-dispatch advancement and starts a 30-second timer.
3. Agent calls `pwsh ./tools/automation/submit-pause-decision.ps1` with `-Decision continue|stop`.
4. Broker polls `harness/automation/requests/pause-decision.json`, validates, forwards `pause_decision` to runtime.
5. Runtime resumes or stops. Decision is recorded in `pause-decision-log.jsonl`.

Timeout default: 30 seconds → `decision = timeout_default_applied, decisionSource = timeout_default` → run stops.

### Capability advertisement (three new bits)

`get-editor-evidence-capability.ps1` now surfaces three additional entries:

| Field | Always supported? | Degraded behavior when false |
|---|---|---|
| `runtimeErrorCapture` | Yes (v1 invariant) | N/A |
| `pauseOnError` | No — requires runtime bridge | Run continues in capture-only mode; `pauseOnErrorMode = "unavailable_degraded_capture_only"` |
| `breakpointSuppression` | No — requires engine hook | Breakpoints still route through the pause-decision flow with `cause = "paused_at_user_breakpoint"` |

### Crash classification

When the game process exits without a clean shutdown handshake:
- `termination = "crashed"` is stamped.
- The runtime's last-error sidecar (`last-error-anchor.json`) is read to populate `lastErrorAnchor`.
- If no error was captured before the crash, `lastErrorAnchor = { "lastError": "none" }`.

**Persistence guarantee (Fix #19):** `runtime-error-records.jsonl` and `last-error-anchor.json` are written through two independent fallback paths so they are present even when the run ends before `persist_latest_bundle` runs:

1. **Coordinator emergency flush** — when `_fail_run_as_crashed` fires, the coordinator writes its own accumulated dedup map to `runtime-error-records.jsonl` (and the anchor sidecar) if the files are missing or empty. The `validationResult.notes` array on the run result will contain `"runtime_error_records: emergency_persisted"` when this path was used, or `"runtime_error_records: none_observed"` when no errors had been recorded at all.
2. **Runtime exit-tree flush** — `_exit_tree` writes the runtime's in-memory dedup map to the same JSONL file under the same missing-or-empty guard, covering clean user-stop cases where `persist_latest_bundle` never ran.

Neither path overwrites a file that `persist_latest_bundle` already wrote.

### Cooperation with feature 006 (input dispatch)

While a pause is outstanding, the broker does NOT advance any queued input-dispatch events. The outstanding pause must be resolved (or timeout) before input dispatch resumes.
