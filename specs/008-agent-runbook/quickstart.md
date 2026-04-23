# Quickstart — Agent Runbook & Parameterized Harness Scripts

Audience: a coding agent (or a human standing in for one) who needs to
verify that the deliverables in this spec are present, well-formed, and
behave as documented.

## Prerequisites

- PowerShell 7+ (`pwsh`) on `PATH`.
- Pester 5+ (already required by `tools/tests/run-tool-tests.ps1`).
- *(Optional, for the live-editor smoke test only)* a Godot editor
  resolvable via `$env:GODOT_BIN` or `godot` / `godot4` / `Godot*` on
  `PATH`, plus an integration-testing sandbox per
  `docs/INTEGRATION_TESTING.md`. **No live editor is required to
  validate this feature's tests.**

## 1. Run the regression suite (no editor needed)

```pwsh
pwsh ./tools/tests/run-tool-tests.ps1
```

Expected: `InvokeRunbookScripts.Tests.ps1` reports passes for, per
script:

- Parameter contract (mutually exclusive `-RequestFixturePath` /
  `-RequestJson`; required `-ProjectRoot`).
- Editor-not-running failure path (mocked stale capability).
- Build / runtime / timeout failure passthrough.
- Success envelope shape (validates against
  `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`).

Plus a static-check test reporting:

- All `RUNBOOK.md` rows resolve to existing files.
- Every fixture under `tools/tests/fixtures/runbook/` validates against
  its upstream schema via `tools/validate-json.ps1`.
- No agent-facing recipe text references `addons/agent_runtime_harness/`
  outside the canonical "do not read" callout (SC-002).

## 2. Inspect the runbook by hand

Open `RUNBOOK.md` from the repo root. Verify:

- Five rows in the order: input dispatch, scene inspection, behavior
  watch, build-error triage, runtime-error triage.
- Every row's "orchestration script", "fixture", and "recipe" links
  resolve.

Open any one recipe under `docs/runbook/<workflow>.md`. Verify:

- The five required H2 sections (Prerequisites, Run it, Expected
  output, Failure handling, Anti-patterns) are present.
- The fenced PowerShell block under "Run it" is a single command.
- "Anti-patterns" contains the canonical "do not read addon source"
  callout.

## 3. Get-Help check

For each orchestration script:

```pwsh
Get-Help ./tools/automation/invoke-input-dispatch.ps1 -Full
Get-Help ./tools/automation/invoke-scene-inspection.ps1 -Full
Get-Help ./tools/automation/invoke-behavior-watch.ps1 -Full
Get-Help ./tools/automation/invoke-build-error-triage.ps1 -Full
Get-Help ./tools/automation/invoke-runtime-error-triage.ps1 -Full
```

Each MUST output complete `.SYNOPSIS`, `.DESCRIPTION`, all
`.PARAMETER` entries, and at least one `.EXAMPLE`. (FR-008.)

## 4. Live-editor smoke test (optional)

Only if you have an integration-testing sandbox set up per
`docs/INTEGRATION_TESTING.md` and an editor running against it.

### 4a. Press Enter

```pwsh
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot integration-testing/<name> `
  -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

Expected stdout: a single JSON envelope with `status = "success"`,
`failureKind = null`, a `manifestPath`, and an `outcome.outcomesPath`
pointing at the captured `input-dispatch-outcomes.jsonl`. Stderr:
`OK: dispatched <N> events; manifest at <path>`.

### 4b. Inspect the scene tree

```pwsh
pwsh ./tools/automation/invoke-scene-inspection.ps1 `
  -ProjectRoot integration-testing/<name>
```

Expected `outcome.sceneTreePath` points at a captured `scene-tree.json`.

### 4c. Editor not running

Stop the editor, then re-run any of the above. Expected exit code
non-zero, stdout JSON `failureKind = "editor-not-running"`, stderr
`FAIL: editor-not-running; launch with: godot --editor --path <ProjectRoot>`.

## 5. Verify success criteria coverage

| Success Criterion | How verified by this quickstart |
|---|---|
| SC-001 (≤5 tool calls per workflow) | Each step in §4 is a single script invocation that performs the entire loop. |
| SC-002 (no addon source pointers) | Static check in §1; manual scan in §2. |
| SC-003 (no false-positive stale reads) | §4c verifies the editor-not-running message; Pester suite covers programmatically. |
| SC-004 (single-call failure classification) | Pester suite in §1 covers build / runtime / timeout passthrough. |
| SC-005 (every workflow has working invocation + fixture) | Static check in §1; manual scan in §2. |
| SC-006 (`Get-Help -Full` complete for every script) | §3, plus Pester static-check in §1. |
