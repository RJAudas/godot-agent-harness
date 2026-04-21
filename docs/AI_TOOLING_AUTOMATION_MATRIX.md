# AI Tooling Automation Matrix

## Purpose

Use this matrix to decide whether a repository concern belongs in instructions, a fixed workflow, a Copilot-native prompt or agent, or a future local skill.

| Need | Best fit | Why | Validation requirement |
|------|----------|-----|------------------------|
| Durable repo or subtree rule | Instructions | Stable guidance should be attached close to the files it governs. | Confirm the rule is concise, non-conflicting, and points to real paths. |
| Deterministic local operation | Scripted workflow | Fixed steps are cheaper and safer than an open-ended agent loop. | Validate output shape and exit behavior locally. |
| Repeated human-invoked diagnosis or drafting task | Prompt artifact | The user chooses when to invoke it and reviews the output. | Seed at least one prompt fixture and expected output. |
| Open-ended multi-step repo task with clear scope | Agent artifact | The artifact can plan, inspect, and iterate when the exact path is not predictable. | Define scope, stop conditions, output shape, and write boundary. |
| Reusable cross-runtime capability bundle | Local skill | Package repeated know-how only after the workflow proves reusable. | Show repeated demand and deterministic supporting assets. |

## Decision rules for this repository

- Prefer instructions for rules that should apply on most tasks or across a subtree.
- Prefer scripts for contract validation, manifest assembly, and other deterministic operations.
- Use prompt artifacts for guided evidence triage or runtime verification where a human still chooses whether to run the workflow.
- Use agent artifacts when the repo task is open-ended enough to justify planning and tool iteration, including end-to-end runtime verification that may need capability reads, brokered requests, and manifest-first inspection.
- Defer local skills until the same workflow repeats across multiple tasks or runtimes.

## Validation routing matrix

| Request shape | Validation mode | Best fit | Why |
|------|----------|----------|-----|
| Unit, contract, framework, or schema check with no running-game claim | Ordinary tests | Existing test runner or validation script | The task can be proven without runtime scenegraph evidence. |
| "Verify at runtime," "test the running code," "make sure the node appears in game," or another runtime-visible claim | Scenegraph Harness runtime verification | Runtime-verification prompt or agent plus the editor-evidence workflow | The task needs a brokered run and persisted runtime evidence. |
| Runtime-visible behavior change plus an existing deterministic direct test surface | Combined validation | Ordinary tests plus runtime-verification workflow | The task needs both code-level and live-runtime proof. |
| Existing evidence manifest with a request to diagnose the result | Evidence triage | Evidence-triage prompt or agent | A fresh run is unnecessary because the manifest-centered bundle already exists. |
| Drive deterministic keyboard or input-action events through the running game | Scenegraph Harness runtime verification with an `inputDispatchScript` | Editor-evidence workflow plus the input-dispatch contract | The validator and runtime dispatch live inside the existing harness and persist a fixed `input-dispatch-outcomes.jsonl` artifact in the run's evidence bundle (see `specs/006-input-dispatch/`). |
| Capture runtime errors and warnings from a running playtest | Scenegraph Harness runtime verification | Editor-evidence workflow with the broker's error-capture path | `runtime-error-records.jsonl` and the `runtimeErrorReporting` manifest block are emitted automatically; no additional request parameters needed (see `specs/007-report-runtime-errors/`). |
| Pause the running game on a runtime error and wait for an agent decision | Scenegraph Harness runtime verification with `submit-pause-decision.ps1` | Pause-on-error flow in the editor broker | Requires `pauseOnError.supported = true` in the capability artifact. Submit `pause-decision.json` via `tools/automation/submit-pause-decision.ps1` within the 30-second window. |

Runtime harness invocation is a routed workflow chosen by task intent.
It is not a replacement for ordinary tests, and evidence triage is not a replacement for a fresh runtime-verification run.

## Safety rules

- Every autonomous artifact must declare a write boundary before it is treated as approval-free.
- Machine-readable run logs are required for autonomous actions.
- If the task requires engine-facing or destructive changes, escalate instead of expanding the boundary informally.

## Runtime error capability routing (specs/007)

| Capability bit | Tool to read it | When `supported = false` |
|---|---|---|
| `runtimeErrorCapture` | `get-editor-evidence-capability.ps1` | Not possible in v1 (always supported when addon loaded). |
| `pauseOnError` | `get-editor-evidence-capability.ps1` | Run proceeds in capture-only degraded mode. Manifest stamps `pauseOnErrorMode = "unavailable_degraded_capture_only"`. No `pause-decision.json` needed. |
| `breakpointSuppression` | `get-editor-evidence-capability.ps1` | Breakpoints fire normally but are routed through the pause-decision flow with `cause = "paused_at_user_breakpoint"`. Same `submit-pause-decision.ps1` applies. |

### New artifact kinds (specs/007)

| Kind | File | Schema |
|---|---|---|
| `runtime-error-records` | `runtime-error-records.jsonl` | `specs/007-report-runtime-errors/contracts/runtime-error-record.schema.json` |
| `pause-decision-log` | `pause-decision-log.jsonl` | `specs/007-report-runtime-errors/contracts/pause-decision-record.schema.json` |

### New tool helper (specs/007)

`tools/automation/submit-pause-decision.ps1` — writes a validated `pause-decision.json` to `harness/automation/requests/pause-decision.json`. Parameters: `-ProjectRoot`, `-RunId`, `-PauseId`, `-Decision (continue|stop)`, `-SubmittedBy`.
