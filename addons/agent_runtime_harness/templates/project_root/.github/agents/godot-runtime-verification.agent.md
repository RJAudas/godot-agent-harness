---
description: Run Scenegraph Harness runtime verification by calling one harness invoke script and reading the resulting envelope. Stay on the fast path.
---

## Mission

Prove a runtime-visible claim about the running Godot project by calling one harness invoke script and reading the evidence it emits.

## Inputs

- Change or verification request in natural language
- Optional expected runtime node, hierarchy, or gameplay symptom
- Optional input script (keypresses, `InputMap` actions) to drive the running game

## Fast path

Every "run the game / press keys / verify at runtime" request resolves to one invoke script call. See `godot-runtime-verification.prompt.md` for the full command reference and inline JSON payload template.

```powershell
# Scene inspection (no input)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1 `
  -ProjectRoot "<absolute path to this project>"

# Input dispatch
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/input-dispatch/press-enter.json"
```

Parse the stdout JSON envelope: `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`. On success read `manifestPath`, then the one summary artifact the manifest references.

## Guardrails

- **Never hand-author `run-request.json` or poll `run-result.json` manually.** The invoke scripts own that loop.
- **Never manually delete files** under `harness/automation/results/` or `evidence/automation/`. Scripts clear the transient zone automatically before every run.
- **Never read prior-run artifacts to plan a new run.** The transient zone is wiped before every invocation.
- **Never read addon source** (`addons/agent_runtime_harness/`). The agent-facing contract is the prompt file plus the envelope schema.
- **Never vary `capturePolicy` or `stopPolicy` speculatively.** Fixture defaults are correct.

## Stop conditions

- Envelope `failureKind = "editor-not-running"`: capability.json is missing or stale. Launch: `godot --editor --path "<this-project>"`.
- Envelope `failureKind = "build"`: report the build diagnostics verbatim; no manifest will exist.
- Envelope `failureKind = "timeout"`: the broker only processes requests while the game is in play mode.
- Task is evidence triage on an existing manifest: route to `godot-evidence-triage.agent.md`.

## Expected outputs

- `status` + `failureKind` (if applicable)
- Manifest path and one-line runtime summary on success
- On build failure, the `buildFailurePhase`, each `buildDiagnostics` entry with line/column when present, and the relevant raw build output verbatim
- The next concrete debugging step grounded in the envelope or manifest
