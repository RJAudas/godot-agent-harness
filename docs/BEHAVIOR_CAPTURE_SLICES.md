# Runtime Behavior Capture Slices

## Purpose

This document breaks runtime behavior capture into small, testable slices for the Godot Agent Harness.
It is focused on debugging time-based gameplay behavior such as a Pong ball that sticks to a wall, slides along it, or fails to reverse velocity after contact.

The design stays plugin-first and extends the existing manifest-centered evidence bundle instead of introducing a second runtime diagnostics system.

## Design guardrails

- Keep capture bounded and agent-directed. Do not log everything every frame by default.
- Reuse the existing evidence bundle flow: manifest first, then only the raw artifacts needed for diagnosis.
- Prefer deterministic capture windows over open-ended streaming.
- Treat runtime-visible behavior as evidence, not prose.
- Keep the first implementation editor-launched and addon-first.

## Recommended ship order

| Slice | Name | Why it ships now | Depends on |
| --- | --- | --- | --- |
| 1 | Runtime query contract | Defines what an agent can ask for | None |
| 2 | Targeted watch sampling | Produces useful time-series data with low overhead | 1 |
| 3 | Triggered capture windows | Captures the right frames without full-run logging | 1, 2 |
| 4 | Invariant-driven persistence | Turns behavior bugs into machine-readable pass or fail outcomes | 2, 3 |
| 5 | Script probes | Explains custom movement logic when node state is not enough | 1, 2 |
| 6 | Manifest and triage integration | Makes the evidence easy for agents to consume | 2, 3, 4 |
| 7 | Live editor stream (optional) | Nice exploratory UX, not required for the core agent loop | 2 |

## Slice 1 - Runtime query contract

**Feature request**

As an agent, I want to declare exactly which runtime behavior data to capture so the harness records only the nodes, properties, cadence, triggers, and invariants relevant to my debugging question.

**What it does**

This slice defines the machine-readable request shape for behavior capture. It is the control surface that later slices execute.

Suggested query fields:

- target nodes or selectors
- sampled properties
- frame cadence
- capture duration or frame budget
- trigger conditions
- ring-buffer size
- invariant list
- persistence policy

**How it fits**

This is the foundation for every later slice. Without it, the harness has no stable, agent-friendly way to request bounded runtime behavior evidence.

**Implementation instructions**

1. Add a behavior-capture request contract that can be passed through session config or per-run override data.
2. Normalize the request at runtime so missing values become explicit defaults instead of implicit behavior.
3. Keep the request independent from one specific game so the same contract works for Pong and later projects.
4. Reject unsupported selectors, properties, or trigger types with explicit machine-readable errors.

**Testable deliverables**

- A documented request schema for behavior capture.
- One valid fixture request for a Pong wall-bounce investigation.
- One invalid fixture request that proves schema or validation rejection.
- A normalized runtime echo or summary that shows what query the harness actually applied.

**Definition of done**

1. A valid query can be loaded and normalized without starting a run.
2. An invalid query fails decisively with a machine-readable reason.
3. The normalized query can be associated with a run and persisted in run metadata.

---

## Slice 2 - Targeted watch sampling

**Feature request**

As an agent, I want the harness to sample a selected set of properties for selected nodes over a bounded frame window so I can inspect how state changes over time without paying the cost of full-scene per-frame logging.

**What it does**

This slice records a bounded trace for watched nodes. For Pong, that likely means `Ball` position, velocity, intended velocity, collision state, last collider, and overlap counters.

**How it fits**

This is the first slice that produces the time-series evidence needed to explain sticky or sliding collisions. It should write the trace artifact that later invariants and summaries reference.

**Implementation instructions**

1. Add a sampler that records only requested properties for requested nodes.
2. Support `every_frame` and `every_n_frames` modes.
3. Cap total frames or duration so traces stay bounded.
4. Write the result as a stable machine-readable trace artifact, ideally `trace.jsonl`.
5. Keep serialization flat and agent-readable. Prefer explicit fields over opaque blobs.

**Testable deliverables**

- A seeded run that writes `trace.jsonl` for a watched ball.
- Trace rows that include frame and timestamp plus the selected watched properties.
- A manifest artifact reference for the trace output.

**Definition of done**

1. A seeded run can capture a bounded trace without logging unrelated nodes.
2. The trace contains the watched properties for the expected frame window.
3. The manifest references the trace artifact successfully.

---

## Slice 3 - Triggered capture windows

**Feature request**

As an agent, I want the harness to keep a small rolling history and persist only the frames around important behavior events so I can see what happened before and after a collision without storing every frame of the whole run.

**What it does**

This slice introduces a ring buffer plus event-triggered persistence. It captures a failure window around events such as:

- wall contact
- overlap start
- overlap persisting beyond N frames
- velocity failing to reverse after contact
- ball speed dropping to zero unexpectedly

**How it fits**

This is the main overhead-control mechanism. It turns continuous sampling into compact, diagnosis-ready windows.

**Implementation instructions**

1. Keep a bounded in-memory ring buffer of recent sampled frames.
2. Add trigger definitions that can request persistence of pre-trigger and post-trigger frames.
3. Record structured events in `events.json` when a trigger fires.
4. Allow manual trigger requests in addition to automatic ones.
5. Include the relevant frame window in artifact metadata when possible.

**Testable deliverables**

- A ring buffer implementation with configurable pre/post frame counts.
- A seeded overlap or wall-contact run that emits `events.json`.
- A persisted trace window showing frames before and after the triggering event.
- Manifest entries that point to the relevant trace and event artifacts.

**Definition of done**

1. A trigger can persist a bounded pre/post frame window without full-run trace retention.
2. The event artifact names the trigger type, source node, frame, and payload.
3. The persisted trace clearly includes the requested pre-trigger and post-trigger frames.

---

## Slice 4 - Invariant-driven persistence

**Feature request**

As an agent, I want the harness to evaluate behavior invariants during runtime and automatically persist the relevant evidence when one fails so I can debug from a small failure bundle instead of a vague report that the run looked wrong.

**What it does**

This slice turns known behavior expectations into machine-readable outcomes. For Pong, likely first invariants are:

- ball clears a wall within N frames after contact
- horizontal velocity reverses after wall contact
- ball speed stays within configured bounds
- ball does not remain overlapping a collider longer than N frames

**How it fits**

This slice transforms raw behavior capture into agent-friendly diagnosis. It is the point where the harness stops being just telemetry and becomes a runtime proof system.

**Implementation instructions**

1. Evaluate invariants against sampled frames and event windows.
2. Persist `invariants.json` with pass, fail, or unknown results.
3. On invariant failure, persist the relevant trace window and any point-in-time snapshot needed for context.
4. Surface the failed invariant in the manifest summary so an agent can route immediately to the right raw artifact.

**Testable deliverables**

- At least two seeded invariant checks for Pong wall behavior.
- A failing fixture where the ball sticks or slides and the invariant report fails correctly.
- A passing fixture where the ball bounces correctly and the invariant report passes.
- Manifest summary output that references the failed invariant and linked artifacts.

**Definition of done**

1. A known sticky-wall scenario produces a deterministic invariant failure.
2. A good bounce scenario passes the same invariant set.
3. The failure report links directly to the trace and event artifacts that explain the result.

---

## Slice 5 - Script probes

**Feature request**

As an agent, I want the movement script to expose selected before-and-after internal values around its update logic so I can see why custom code made the wrong bounce decision when node state alone is not enough.

**What it does**

This slice adds opt-in probe hooks for logic-driven movement. It is specifically meant for cases where the ball is not using Godot physics and the important failure cause lives inside script-local variables or branch decisions.

Examples:

- intended velocity before resolution
- collision candidate list
- chosen bounce normal
- branch outcome such as `reflect_x = false`
- corrected position before and after wall resolution

**How it fits**

This is not the default path. It is a deeper layer used when watch sampling plus invariants still do not explain the failure.

**Implementation instructions**

1. Provide a small probe API that game scripts can call explicitly.
2. Keep probes request-scoped and opt-in so normal runs do not pay the cost.
3. Route probe output into existing behavior evidence artifacts rather than inventing a separate opaque log.
4. Distinguish probe data from observed node-state data in the output shape.

**Testable deliverables**

- A minimal probe helper API callable from a custom movement script.
- A seeded custom Pong script that emits before/after values for wall-bounce resolution.
- Persisted probe entries tied to the same run and frame window as the sampled trace.

**Definition of done**

1. A scripted movement fixture can emit probe data only when requested.
2. Probe output is correlated to frame numbers and source script or node path.
3. The evidence explains at least one failure cause that is not visible from node state alone.

---

## Slice 6 - Manifest and triage integration

**Feature request**

As an agent, I want behavior-capture runs to arrive as the same kind of manifest-centered evidence bundle used elsewhere in the harness so I can read the manifest first, then open only the trace, events, invariants, or snapshot files needed to explain the failure.

**What it does**

This slice wires the new behavior artifacts into the current evidence handoff model.

Expected artifacts for a behavior-focused run:

- `trace.jsonl`
- `events.json`
- `invariants.json`
- `scene-snapshot.json` when a point-in-time snapshot is useful
- manifest summary fields that call out the failing behavior

**How it fits**

This slice keeps behavior capture aligned with the existing scenegraph and automation workflow instead of creating a second agent-consumption path.

**Implementation instructions**

1. Extend artifact registration and manifest-writing logic to include behavior-capture artifacts.
2. Add summary-builder logic that can highlight behavior failures, not just scenegraph outcomes.
3. Preserve manifest-first triage expectations: the summary should tell the agent which artifact to open next.
4. Add eval fixtures that prove another agent can diagnose a failure from the bundle.

**Testable deliverables**

- Manifest support for trace, events, and invariant artifacts from a real behavior run.
- A summary entry that points to the failing invariant and failure window.
- One eval fixture bundle for a sticky-ball failure and one for a successful bounce.

**Definition of done**

1. A behavior run produces a valid manifest-centered bundle.
2. The manifest summary identifies the key failure without reading every raw file.
3. The referenced artifacts are sufficient for post-run diagnosis.

---

## Slice 7 - Live editor stream (optional)

**Feature request**

As a maintainer or operator, I want an optional live stream of the currently watched behavior fields in the editor so I can inspect a run interactively while keeping persisted artifacts as the primary agent contract.

**What it does**

This slice adds an editor UX for active runs. It is useful for manual debugging and fast iteration, but it is not required for the core agent workflow.

**How it fits**

This is a convenience layer on top of the same sampled and triggered data model built in earlier slices.

**Implementation instructions**

1. Reuse the existing debugger transport rather than creating a separate live socket path.
2. Keep the live stream bounded to the active watch list.
3. Do not make persisted diagnosis depend on the live view.
4. Make it clear that saved artifacts remain the source of truth after the run.

**Testable deliverables**

- An editor-side live view for currently watched fields.
- A seeded run where the live view updates during playtesting.
- Confirmation that the same run still persists the expected post-run evidence bundle.

**Definition of done**

1. The live stream reflects the active watch query during a run.
2. The run remains diagnosable from persisted artifacts even if nobody watches the live stream.
3. Live UX failures do not block bundle persistence.

## Suggested MVP boundary

If the goal is to debug Pong-like bounce failures quickly with minimal overhead, the first MVP should include:

1. Slice 1 - Runtime query contract
2. Slice 2 - Targeted watch sampling
3. Slice 3 - Triggered capture windows
4. Slice 4 - Invariant-driven persistence
5. Slice 6 - Manifest and triage integration

Slice 5 should be added when the game uses custom script-driven motion and the sampled node state is not enough to explain the bug.
Slice 7 should remain optional until the persisted evidence workflow is proven.

## First seeded scenario to implement

Use a deterministic Pong fixture that asks for:

- watch target: `/root/Main/Ball`
- properties: `position`, `velocity`, `intended_velocity`, `collision_state`, `last_collider`, `overlap_frames`
- cadence: every frame
- ring buffer: 20 frames
- triggers: `wall_contact`, `overlap_persisted`, `velocity_not_reversed`
- invariants:
  - `ball-clears-wall-within-two-frames`
  - `horizontal-velocity-reverses-after-wall-contact`

Expected persisted bundle:

- manifest summary says the ball remained overlapped or failed to reverse velocity
- `trace.jsonl` shows the failure window
- `events.json` shows collision and trigger events
- `invariants.json` records the failing rule
- `scene-snapshot.json` is included only if the failure needs point-in-time hierarchy or property context
