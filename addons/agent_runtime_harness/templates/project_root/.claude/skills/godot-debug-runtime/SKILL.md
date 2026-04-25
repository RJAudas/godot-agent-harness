---
name: "godot-debug-runtime"
description: "Run the Godot game with pause-on-error enabled and capture any GDScript runtime errors (null dereferences, invalid calls, missing nodes). Use when the user asks why the game crashes, why something throws at runtime, or to reproduce a runtime error."
argument-hint: "(optional) fixture path"
compatibility: "Requires a Godot editor running against the target project and access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-runtime-error-triage.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as an optional fixture path. **Default: `{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json`** — this fixture sets `stopAfterValidation=false` so the playtest runs past startup validation and `_ready` / early-frame errors are captured. (For a clean game the run ends at the orchestration's `-TimeoutSeconds` budget — that's the expected "no errors caught" signal.) Default project root is the current project (`.`).

## Execution

`-EnsureEditor` idempotently launches a Godot editor for the project (or reuses one if already running and capability.json is fresh). Pass it on every call.

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot "<project-root>" -EnsureEditor `
  -RequestFixturePath "<fixture-path-or-default>"
```

Pass `-IncludeFullStack` when the user asks for full stack traces.

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` (no errors) or `"failure"` |
| `failureKind` | `null` on success; see failure table |
| `manifestPath` | Absolute path to `evidence-manifest.json` |
| `outcome.runtimeErrorRecordsPath` | Absolute path to `runtime-error-records.jsonl` |
| `outcome.latestErrorSummary.file` / `.line` / `.message` | Most-recent runtime error's location and message |
| `outcome.terminationReason` | `completed` / `stopped_by_agent` / `stopped_by_default_on_pause_timeout` / `crashed` / `killed_by_harness` |

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Auto-launch failed (e.g. missing `$env:GODOT_BIN`, project failed to import) | Read `diagnostics[0]` for the underlying reason; common fix is to ensure `$env:GODOT_BIN` points at a Godot 4 binary |
| `build` | GDScript compile error before runtime started | Use `/godot-debug-build` for richer build diagnostics |
| `runtime` | Runtime error captured (expected outcome for this skill) | Report `outcome.latestErrorSummary`; do not treat as harness failure |
| `timeout` | Run did not complete in time | Increase `-TimeoutSeconds` or check if the editor is frozen |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not submit pause-decisions inline** — this skill is read-only error surfacing.
- **Do not blind-retry on `runtime`** — a runtime failure is the expected signal; report it.
