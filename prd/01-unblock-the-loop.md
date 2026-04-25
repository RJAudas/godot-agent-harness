# Pass 1 — Unblock the loop

## Goal

Fix the four issues that prevent a fresh agent from getting clean evidence out of any runtime-verification workflow. After this pass, an agent can call `invoke-scene-inspection.ps1` (or any of the other four runtime invokers), receive `status=success`, follow `manifestPath`, and read the artifacts the manifest references — none of which currently work end-to-end.

This is the highest-impact pass. It does **not** do refactors, ergonomics improvements, or test hardening — those are passes 2 and 3.

## Quick context (read first if you're fresh)

The repo is a Godot harness for AI agents. Two sides talk via a file broker:

- **Editor side** (a Godot editor process running against a sandbox project) watches the canonical request path `harness/automation/requests/run-request.json` and writes results back to `harness/automation/results/`.
- **Agent side** invokes `tools/automation/invoke-<workflow>.ps1` scripts. Each script: capability-checks the editor, writes a request, polls `run-result.json`, reads `evidence-manifest.json`, emits a JSON envelope on stdout.

The shared orchestration helpers live in [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1). Five runtime workflows exist:

| Workflow | Script | Payload route |
|---|---|---|
| Scene inspection | `invoke-scene-inspection.ps1` | inline (synthesized in-script) |
| Input dispatch | `invoke-input-dispatch.ps1` | fixture or inline JSON via `Resolve-RunbookPayload` |
| Behavior watch | `invoke-behavior-watch.ps1` | fixture or inline JSON via `Resolve-RunbookPayload` |
| Build-error triage | `invoke-build-error-triage.ps1` | fixture or inline JSON via `Resolve-RunbookPayload` |
| Runtime-error triage | `invoke-runtime-error-triage.ps1` | fixture or inline JSON via `Resolve-RunbookPayload` |

Both routes converge on the same canonical path (the broker only watches one). Every runtime workflow is affected by the bugs in this pass.

For deeper architectural context: [CLAUDE.md](../CLAUDE.md), [AGENTS.md](../AGENTS.md), [RUNBOOK.md](../RUNBOOK.md).

## Issues in this pass

### C1 — Validator-vs-broker race in `Invoke-RunbookRequest`

**Where**: [tools/automation/RunbookOrchestration.psm1:262-274](../tools/automation/RunbookOrchestration.psm1#L262-L274) (validation step) plus [Resolve-RunbookPayload:211-212](../tools/automation/RunbookOrchestration.psm1#L211-L212) and [invoke-scene-inspection.ps1:166-175](../tools/automation/invoke-scene-inspection.ps1#L166-L175) (the two write paths that feed the validator).

**Symptom**: every successful run is reported to the agent as `status=failure, failureKind=request-invalid` with a diagnostic like:
```
Schema validator failed to run (exit 1). Output: Resolve-Path: ...
Cannot find path '<sandbox>/harness/automation/requests/run-request.json' because it does not exist.
```
Meanwhile `harness/automation/results/run-result.json` shows `finalStatus=completed, terminationStatus=stopped_cleanly` and the editor has produced a valid manifest. The agent receives a failure envelope and discards a perfectly good run.

**Repro** (live editor required, see "How to validate the whole pass" below):
```powershell
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
# → exit 1, JSON envelope with failureKind=request-invalid, ANSI noise in diagnostics[0]
# → meanwhile harness/automation/results/run-result.json shows finalStatus=completed
```

**Root cause**: the orchestrator writes the request to the canonical path the broker watches (it has to — the broker only listens to that one path; see comment at [RunbookOrchestration.psm1:203-206](../tools/automation/RunbookOrchestration.psm1#L203-L206)). Then it calls the validator, which calls `Resolve-Path` on that same path. Between the write and the `Resolve-Path` call, the editor's FileSystemWatcher fires, the broker reads the file, and the broker deletes it. By the time `Resolve-Path` runs, the file is gone.

The current sequence in `Invoke-RunbookRequest`:
```
Resolve-RunbookPayload writes run-request.json   <-- broker may consume here
                                                 <-- or here
Invoke-RunbookRequest validates run-request.json <-- file is already gone
```

**Fix**: validate before the broker can see the file. Two viable options.

**Option A (recommended) — validate in-memory, write atomically:**

Move validation out of `Invoke-RunbookRequest` and into `Resolve-RunbookPayload`. After parsing the payload but before writing to the canonical path, write to a temp file first, validate the temp file, then atomic-rename into the canonical position so the broker only ever sees a known-valid file:

```powershell
# In Resolve-RunbookPayload, after $payload['expectationFiles'] default but before write:
$canonicalPath = Join-Path $requestsDir 'run-request.json'
$tmpPath       = "$canonicalPath.tmp"

$payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmpPath -Encoding utf8

$schemaPath = 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
$validation = Invoke-Helper -ScriptPath 'tools/validate-json.ps1' -ArgumentList @(
    '-InputPath', $tmpPath, '-SchemaPath', $schemaPath, '-AllowInvalid'
)
if ($validation.ExitCode -ne 0) {
    Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    throw "Schema validator could not run: $($validation.CapturedOutput)"
}
$parsed = $validation.CapturedOutput | ConvertFrom-Json -Depth 20
if (-not $parsed.valid) {
    Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    throw "Run request does not satisfy schema '$schemaPath': $($parsed.error)"
}

Move-Item -LiteralPath $tmpPath -Destination $canonicalPath -Force
```

Then strip the now-redundant validation block from `Invoke-RunbookRequest` (lines 252-294) — keep only the `runResultPath` poll loop.

You also need to thread the same change through `invoke-scene-inspection.ps1`, which writes inline at [lines 160-167](../tools/automation/invoke-scene-inspection.ps1#L160-L167) and bypasses `Resolve-RunbookPayload` entirely. The cleanest fix is part of issue **H3** in pass 2 (have scene-inspection call `Resolve-RunbookPayload` like its peers); for this pass, duplicate the tmp-write-validate-rename block at lines 160-167 too.

**Option B — keep validation where it is, but write to `.tmp` first:**

Less invasive. Change `Resolve-RunbookPayload` to write to `run-request.json.tmp` and return that path. Change `Invoke-RunbookRequest` to validate the `.tmp`, then atomic-rename it to `run-request.json` before starting the poll. Same effect, just keeps the validation responsibility inside `Invoke-RunbookRequest`. Slightly more parameter plumbing.

**How to verify**:
1. Run the live integration test in "How to validate the whole pass" below.
2. Stdout envelope should show `status=success`, non-null `manifestPath`, empty `failureKind`.
3. `diagnostics` should be `[]` (combined with H1 fix).

---

### C2 — `artifactRoot` is a fixture-test path baked into production

**Where**:
- Hardcoded in production payload: [tools/automation/invoke-scene-inspection.ps1:152](../tools/automation/invoke-scene-inspection.ps1#L152)
- Present in every fixture: [tools/tests/fixtures/runbook/](../tools/tests/fixtures/runbook/) — confirmed in `input-dispatch/press-enter.json:7`, `behavior-watch/single-property-window.json:7`, `inspect-scene-tree/startup-capture.json:8`, `runtime-error-triage/run-and-watch-for-errors.json` (and the build-error one).
- Honored by the runtime when writing manifest references (see addon source under `addons/agent_runtime_harness/runtime/` — touch this only as part of fixing this issue).

**Symptom**: the editor writes evidence files to `outputDirectory` (e.g. `res://evidence/automation/<requestId>`) but stamps the manifest's `artifactRefs[*].path` and `run-result.manifestPath` with `artifactRoot` (e.g. `tools/tests/fixtures/runbook/inspect-scene-tree/evidence/<requestId>`). Concrete example from a real run in this repo:

- Real artifact location: [integration-testing/probe/evidence/automation/runbook-scene-inspection-20260425T145644Z-b1cc65/](../integration-testing/probe/evidence/automation/runbook-scene-inspection-20260425T145644Z-b1cc65/)
- Manifest claims (under `artifactRefs[*].path`): `tools/tests/fixtures/runbook/inspect-scene-tree/evidence/runbook-scene-inspection-20260425T145644Z-b1cc65/scenegraph-snapshot.json` — **does not exist anywhere**.

The documented agent flow ("read `manifestPath` → read each artifact in `artifactRefs`") FileNotFounds at every hop.

**Root cause**: two fields encode the same intent (where evidence lives), but only one (`outputDirectory`) drives writes. `artifactRoot` is dead state that gets silently propagated into the manifest.

**Fix**: drop `artifactRoot` entirely. Make `outputDirectory` the single source of truth.

Three coordinated changes:

1. **Strip `artifactRoot` from production code.** In [invoke-scene-inspection.ps1:152](../tools/automation/invoke-scene-inspection.ps1#L152), delete the line:
   ```powershell
   artifactRoot     = "tools/tests/fixtures/runbook/inspect-scene-tree/evidence/$requestId"
   ```

2. **Strip `artifactRoot` from all 7 fixtures** under [tools/tests/fixtures/runbook/](../tools/tests/fixtures/runbook/). Just delete the field from each JSON. The fixture's `outputDirectory` becomes the only path field.

3. **Update the runtime** to use `outputDirectory` for manifest references. The relevant code is in `addons/agent_runtime_harness/runtime/` (look for whichever component writes `evidence-manifest.json` — likely the scenegraph autoload or a sibling module). Replace any read of `request.artifactRoot` with `request.outputDirectory`. Per [CLAUDE.md](../CLAUDE.md), reading addon source is allowed when the task itself is fixing the addon — this issue qualifies.

4. **Run `pwsh ./tools/check-addon-parse.ps1`** after the runtime change to confirm GDScript still parses cleanly. Non-zero exit is a blocking failure.

5. **Update the request schema**: [specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json](../specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json) likely declares `artifactRoot` as required — remove it from `required[]` and from `properties{}`.

**Alternative (less invasive but uglier)**: keep both fields but force them to point at the same place — set `artifactRoot` = `outputDirectory` everywhere, and update the runtime to use whichever it currently uses for refs. Two fields with the same value forever is a code smell; recommend the drop instead.

**How to verify**:
1. Re-run scene-inspection per the live test below.
2. Open the manifest at the path the envelope reports.
3. For each entry in `artifactRefs[]`, `Test-Path -LiteralPath <path>` should return `True`.
4. The path stem should be `evidence/automation/<requestId>/`, not `tools/tests/fixtures/...`.

---

### C3 — Deploy templates leak literal `.TrimEnd()` into CLAUDE.md and AGENTS.md

**Where**: [tools/deploy-game-harness.ps1:287-292](../tools/deploy-game-harness.ps1#L287-L292) (`Get-AgentsFileContent`) and [tools/deploy-game-harness.ps1:318-324](../tools/deploy-game-harness.ps1#L318-L324) (`Get-ClaudeFileContent`).

**Symptom**: every freshly-deployed sandbox where these files don't already exist (the new-file branch) gets a literal `.TrimEnd()` line at the end of the file. Confirmed in the current sandbox: tail of [integration-testing/probe/CLAUDE.md](../integration-testing/probe/CLAUDE.md) and [integration-testing/probe/AGENTS.md](../integration-testing/probe/AGENTS.md) both end with `.TrimEnd()`.

**Root cause**: a here-string interpolation bug. The current code:

```powershell
function Get-ClaudeFileContent {
    return @"
# CLAUDE.md

$(Get-ClaudeInstructionsBlock).TrimEnd()
"@
}
```

`$(Get-ClaudeInstructionsBlock)` evaluates the function call inside the interpolation, but `.TrimEnd()` lives **outside** the `$(...)` parens, so it's emitted as literal text after the function-call result. Same bug in `Get-AgentsFileContent`.

**Fix**: wrap the call AND the method invocation inside the interpolation parens, or use a temp variable.

```powershell
# Option 1: one-liner
function Get-ClaudeFileContent {
    return @"
# CLAUDE.md

$((Get-ClaudeInstructionsBlock).TrimEnd())
"@
}

# Option 2: temp variable (more readable)
function Get-ClaudeFileContent {
    $block = (Get-ClaudeInstructionsBlock).TrimEnd()
    return @"
# CLAUDE.md

$block
"@
}
```

Apply the same fix to `Get-AgentsFileContent`.

The existing-file path uses `Set-OrAppendManagedBlock` and is unaffected — only the new-file branch is broken.

**How to verify**:
```powershell
pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru
# In bash:
tail -3 integration-testing/probe/CLAUDE.md
tail -3 integration-testing/probe/AGENTS.md
# Neither should end with `.TrimEnd()`.
```

Add a Pester assertion to [tools/tests/ScaffoldSandbox.Tests.ps1](../tools/tests/ScaffoldSandbox.Tests.ps1) — after the existing scaffold test, `Get-Content $claudePath -Raw | Should -Not -Match '\.TrimEnd\(\)'`.

---

### H1 — ANSI escape codes leak into the JSON envelope's `diagnostics`

**Where**: [tools/automation/RunbookOrchestration.psm1:51](../tools/automation/RunbookOrchestration.psm1#L51) (`Invoke-Helper` captures `2>&1` from a child pwsh, which renders errors with ANSI color codes by default). The captured text gets stuffed verbatim into envelope diagnostics at [line 271](../tools/automation/RunbookOrchestration.psm1#L271).

**Symptom**: failure envelopes contain raw escape sequences:
```json
"diagnostics": ["Schema validator failed to run (exit 1). Output: [31;1mResolve-Path: ...[0m"]
```

Any downstream `jq`, `JSON.parse`, or human-eyeballing the envelope sees garbage. Reproduced live alongside C1 in this session.

**Root cause**: PowerShell 7 emits ANSI escapes for error rendering by default. `Invoke-Helper` doesn't normalize them.

**Fix**: strip ANSI from `$capturedText` in `Invoke-Helper` before returning. One line:

```powershell
# In Invoke-Helper, replace lines 54-58 with:
$capturedText = if ($null -ne $captured) {
    ($captured | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
} else {
    ''
}
$capturedText = [regex]::Replace($capturedText, '\x1B\[[0-?]*[ -/]*[@-~]', '')
```

The regex matches CSI sequences (`ESC [ ... terminator`), which covers all the color/format codes pwsh emits.

(Alternative: spawn the child pwsh with `$PSStyle.OutputRendering = 'PlainText'` injected. Works, but more invasive — you have to wrap the script call in `-Command "& { $PSStyle...; & '$path' @args }"` and properly quote `$ArgumentList`. The regex strip is simpler and just as effective.)

**How to verify**:
1. Trigger any failure envelope (e.g. invoke-scene-inspection against a not-running editor): `pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe` (with no editor running).
2. Stdout JSON `diagnostics[0]` should be plain ASCII with no `` sequences.

After C1+C2+H1 land, the success envelope's `diagnostics` should be `[]`.

## How to validate the whole pass

### Static checks (no editor needed)

```powershell
pwsh ./tools/tests/run-tool-tests.ps1
```

Expectation: all existing Pester tests still pass. This pass introduces no test churn beyond:
- New scaffold-sandbox assertion that CLAUDE.md/AGENTS.md don't contain `.TrimEnd()` (C3).
- New schema test that `automation-run-request.schema.json` does NOT require `artifactRoot` (C2).

If you delete `artifactRoot` from the schema, any test fixture or sample run-request that still includes it should still pass schema validation (extra properties are typically allowed) — but **also** verify by running:
```powershell
pwsh ./tools/validate-json.ps1 `
    -InputPath tools/tests/fixtures/runbook/input-dispatch/press-enter.json `
    -SchemaPath specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json
```

### Live integration test (Godot editor required)

Prerequisites:
- `$env:GODOT_BIN` set to a Godot 4.6 binary, OR `godot`/`godot4` on PATH. The console build (`*_console.exe` on Windows) is preferred for stable stdout.
- The probe sandbox already exists from prior session work. Re-create cleanly with `pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru`.

Steps:

```powershell
# 1. Re-scaffold (also exercises C3 fix)
pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru

# 2. Launch the editor (background). Use the console exe on Windows for log capture.
$proc = Start-Process -FilePath $env:GODOT_BIN `
    -ArgumentList @('--editor', '--path', './integration-testing/probe', '--verbose') `
    -PassThru -RedirectStandardOutput './integration-testing/probe/.editor.log' `
    -RedirectStandardError './integration-testing/probe/.editor.err'

# 3. Wait for capability.json to appear (cold-start ~30s on first launch).
$cap = './integration-testing/probe/harness/automation/results/capability.json'
while (-not (Test-Path $cap)) { Start-Sleep -Milliseconds 500 }
"capability ready"

# 4. Run scene inspection.
$envelope = pwsh ./tools/automation/invoke-scene-inspection.ps1 `
    -ProjectRoot ./integration-testing/probe | ConvertFrom-Json

# 5. Assertions.
$envelope.status      | ForEach-Object { if ($_ -ne 'success') { throw "expected success, got $_" } }
$envelope.failureKind | ForEach-Object { if ($_ -ne $null)     { throw "expected null failureKind" } }
$envelope.diagnostics | ForEach-Object { if (@($_).Count -ne 0) { throw "expected empty diagnostics" } }

# 6. Manifest must exist and reference real files.
Test-Path $envelope.manifestPath | ForEach-Object { if (-not $_) { throw "manifestPath missing on disk" } }
$manifest = Get-Content $envelope.manifestPath -Raw | ConvertFrom-Json
foreach ($ref in $manifest.artifactRefs) {
    $abs = if ([System.IO.Path]::IsPathRooted($ref.path)) { $ref.path } else { Join-Path $PWD $ref.path }
    Test-Path $abs | ForEach-Object { if (-not $_) { throw "artifact missing: $abs" } }
}

# 7. Stop the editor.
Get-Process Godot* -ErrorAction SilentlyContinue | Stop-Process -Force
```

Repeat steps 4-7 with the other four runtime invokers using fixtures from `tools/tests/fixtures/runbook/<workflow>/`. All five must pass.

## Out of scope for this pass

- **Pass 2** ([02-dry-ergonomics.md](02-dry-ergonomics.md)): refactor scene-inspection to share `Resolve-RunbookPayload`; ship an editor-launch helper so step 2 above isn't manual; fix pin/unpin exit-code semantics.
- **Pass 3** ([03-hardening-tests.md](03-hardening-tests.md)): clean the `requests/` dir between runs; mock the broker in Pester so C1-class regressions get caught in CI; tighten the silent-wipe behavior of transient cleanup; remove hardcoded `pwsh`.
- **Pass 4** ([04-polish.md](04-polish.md)): scaffold-standalone polish, fix Get-Help examples that point at a non-existent `pong` sandbox, document the junction trick, requestId-suffix `outputDirectory`.

Do not touch addon source for any reason other than C2's runtime fix. Do not change the broker protocol shape. Do not migrate to a per-request filename — that breaks the broker (see [comment at line 203-206](../tools/automation/RunbookOrchestration.psm1#L203-L206)).
