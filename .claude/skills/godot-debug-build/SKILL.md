---
name: "godot-debug-build"
description: "Run the Godot project and capture any build or compile errors (GDScript parse errors, bad resource paths, missing scripts). Use when the user asks about compile failures, parse errors, or why the game won't build."
argument-hint: "(optional) fixture path; defaults to tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json"
compatibility: "Requires a Godot editor running against the target project and access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-build-error-triage.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as an optional fixture path. Default: `tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json`. Ask the user which project root to target.

## Execution

```powershell
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
  -ProjectRoot "<project-root>" `
  -RequestFixturePath "<fixture-path-or-default>"
```

Pass `-IncludeRawBuildOutput` when the user asks for the raw build output path.

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` (build clean) or `"failure"` |
| `failureKind` | `null` on clean build; `build` when compile errors captured |
| `manifestPath` | Absolute path to `evidence-manifest.json` |
| `outcome.firstDiagnostic.file` / `.line` / `.column` / `.message` | First GDScript compile error's location and message |
| `outcome.rawBuildOutputPath` | Absolute path to raw build output (only when `-IncludeRawBuildOutput` was passed) |
| `outcome.runResultPath` | Absolute path to `harness/automation/results/run-result.json` — read this for the full diagnostics array if `firstDiagnostic` is null |

On `failureKind=build`, report `firstDiagnostic.file:line: message` verbatim to the user — do not paraphrase. If `firstDiagnostic` is null, read `outcome.runResultPath` for the full `buildDiagnostics[]` array.

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Capability missing or stale | Tell the user to launch: `godot --editor --path "<project-root>"` |
| `build` | Compile error captured (expected outcome for this skill) | Report `outcome.firstDiagnostic` verbatim; no manifest may exist |
| `runtime` | Build succeeded but runtime failed | Use `/godot-debug-runtime` for runtime-error details |
| `timeout` | Build did not complete | Editor may be frozen |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not paraphrase build diagnostics** — report `file`, `line`, `column`, `message` verbatim.
- **Do not treat `failureKind=build` as a harness failure** — it's the expected signal for this skill.
