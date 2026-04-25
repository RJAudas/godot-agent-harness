---
name: "godot-debug-build"
description: "Run the Godot project and capture any build or compile errors (GDScript parse errors, bad resource paths, missing scripts). Use when the user asks about compile failures, parse errors, or why the game won't build."
argument-hint: "(optional) fixture path"
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

Treat `$ARGUMENTS` as an optional fixture path. Default: `{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json`. Default project root is the current project (`.`).

## Execution

`-EnsureEditor` idempotently launches a Godot editor for the project (or reuses one if already running and capability.json is fresh). Pass it on every call.

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-build-error-triage.ps1 `
  -ProjectRoot "<project-root>" -EnsureEditor `
  -RequestFixturePath "<fixture-path-or-default>"
```

Pass `-IncludeRawBuildOutput` when the user asks for the raw build output path.

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` (build clean) or `"failure"` |
| `failureKind` | `null` on clean build; `build` when compile errors captured |
| `manifestPath` | Absolute path to `evidence-manifest.json` |
| `outcome.firstDiagnostic.file` / `.line` / `.message` | First GDScript compile error's location and message |
| `outcome.rawBuildOutputPath` | Absolute path to raw build output (only when `-IncludeRawBuildOutput` was passed) |

On `failureKind=build`, report `firstDiagnostic` verbatim — do not paraphrase.

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Auto-launch failed (e.g. missing `$env:GODOT_BIN`, project failed to import) | Read `diagnostics[0]` for the underlying reason; common fix is to ensure `$env:GODOT_BIN` points at a Godot 4 binary |
| `build` | Compile error captured (expected outcome) | Report `outcome.firstDiagnostic` verbatim; no manifest may exist |
| `runtime` | Build succeeded but runtime failed | Use `/godot-debug-runtime` for runtime-error details |
| `timeout` | Build did not complete | Editor may be frozen |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not paraphrase build diagnostics** — report `file`, `line`, `column`, `message` verbatim.
- **Do not treat `failureKind=build` as a harness failure** — it's the expected signal for this skill.
