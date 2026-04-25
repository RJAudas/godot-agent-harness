# Pass 4 — Polish

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), and [pass 3](03-hardening-tests.md) deliver the working loop, ergonomic UX, and CI hardening, this pass cleans up first-impression friction. Four issues, all low-impact individually but collectively make the harness feel rough:

- **L1**: `tools/scaffold-sandbox.ps1` produces a project that needs `tools/deploy-game-harness.ps1` chained after to be functional. The scaffold always chains, but the surface invites confusion if anyone runs them separately.
- **L2**: multiple invoke-script `Get-Help` examples reference a sandbox path (`integration-testing/pong`) that doesn't ship in the repo. First-time agents copy-pasting the example get a not-found.
- **L3**: `tools/check-addon-parse.ps1` uses `cmd /c mklink /J` for Windows junctions instead of `New-Item -SymbolicLink`. The reasoning (avoiding Developer Mode requirement) is undocumented, inviting a "simplification" PR that breaks parse-checks.
- **M6**: fixture `outputDirectory` is a static name (e.g. `runbook-input-dispatch`), not requestId-suffixed. Collisions across runs are prevented only because cleanup wipes the dir.

## Quick context (read first if you're fresh)

The harness is a Godot tooling project that gives AI agents machine-readable runtime evidence. Two surfaces touch this pass:

- **Sandbox scaffolding**: `tools/scaffold-sandbox.ps1` creates a minimal Godot 4.6 project under `integration-testing/<name>/` and chains into `tools/deploy-game-harness.ps1` to install the addon, autoload, agent docs, etc. Both are PowerShell. Pester coverage is in [tools/tests/ScaffoldSandbox.Tests.ps1](../tools/tests/ScaffoldSandbox.Tests.ps1).
- **Runtime invoke scripts**: live in `tools/automation/invoke-*.ps1`. Each carries `Get-Help` documentation in a comment-based header that agents read to discover usage.
- **Addon parse-check**: `tools/check-addon-parse.ps1` is a headless GDScript syntax check that runs the addon under Godot in `--headless --editor --quit-after 2` mode. It needs the addon to appear under the test project's `addons/` directory; rather than copy the whole addon every time, it junctions/symlinks.

For deeper context: [CLAUDE.md](../CLAUDE.md), [AGENTS.md](../AGENTS.md), [RUNBOOK.md](../RUNBOOK.md), [tools/README.md](../tools/README.md).

## Issues in this pass

### L1 — Scaffold-sandbox standalone produces a non-functional project

**Where**: [tools/scaffold-sandbox.ps1:78-93](../tools/scaffold-sandbox.ps1#L78-L93) (the `project.godot` body) and [lines 115-126](../tools/scaffold-sandbox.ps1#L115-L126) (the deploy-chain).

The sandbox-scaffold function writes a minimal `project.godot`:

```ini
[application]
config/name="<name>"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6")
```

…and only the `[application]` section. The harness-required `[autoload]` and `[editor_plugins]` blocks come later via the chained `tools/deploy-game-harness.ps1` call at lines 115-116. Currently fine because the chain is unconditional.

**Symptom (latent)**: if anyone ever runs scaffold without the deploy step (e.g., `-SkipDeploy` flag is added later, or someone copies the scaffold logic into a one-off), they get a Godot project that opens but has no harness wiring — and no clear signal of what's missing.

**Fix**: this is borderline a non-issue. Two reasonable options:

**Option A (do nothing, document)**: add a comment in `scaffold-sandbox.ps1` near the `project.godot` synthesis explaining that the autoload and plugin blocks are intentionally absent — they belong to `deploy-game-harness.ps1` because they reference addon paths that scaffold doesn't know about. Anyone adding a `-SkipDeploy` flag in the future will see the comment.

**Option B (merge concerns)**: have scaffold-sandbox refuse to run without the deploy step. Remove any pretense of standalone use. Update the script to throw if you try to disable deployment. Cleaner contract but reduces flexibility.

Recommend Option A. The current architecture cleanly separates "create a Godot project" from "install the harness into a Godot project" — that's a useful separation if anyone ever wants to deploy the harness into a pre-existing project they didn't scaffold.

**How to verify**:
1. Re-run `pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru`.
2. Open `integration-testing/probe/project.godot` and confirm the `[autoload]` and `[editor_plugins]` blocks are present (added by the chained deploy).
3. The new comment in `scaffold-sandbox.ps1` is the only edit if you choose Option A.

---

### L2 — `Get-Help` examples reference `integration-testing/pong` (which doesn't exist)

**Where**: every runtime invoke script's `.EXAMPLE` block. Concrete instances:
- [invoke-input-dispatch.ps1:42](../tools/automation/invoke-input-dispatch.ps1#L42), [49](../tools/automation/invoke-input-dispatch.ps1#L49)
- [invoke-behavior-watch.ps1:37](../tools/automation/invoke-behavior-watch.ps1#L37), [44](../tools/automation/invoke-behavior-watch.ps1#L44)
- [invoke-build-error-triage.ps1:43](../tools/automation/invoke-build-error-triage.ps1#L43), [51](../tools/automation/invoke-build-error-triage.ps1#L51)
- [invoke-runtime-error-triage.ps1:42](../tools/automation/invoke-runtime-error-triage.ps1#L42), [51](../tools/automation/invoke-runtime-error-triage.ps1#L51)
- [invoke-pin-run.ps1:35](../tools/automation/invoke-pin-run.ps1#L35), [42](../tools/automation/invoke-pin-run.ps1#L42)
- [invoke-unpin-run.ps1:30](../tools/automation/invoke-unpin-run.ps1#L30), [37](../tools/automation/invoke-unpin-run.ps1#L37)
- [invoke-list-pinned-runs.ps1:23](../tools/automation/invoke-list-pinned-runs.ps1#L23)

All cite `-ProjectRoot integration-testing/pong`. No such sandbox ships in the repo (`pong` exists only as a fixture under `tools/tests/fixtures/pong-testbed/`).

**Symptom**: an agent runs `Get-Help tools/automation/invoke-input-dispatch.ps1 -Examples`, copy-pastes the example verbatim, and gets a "directory not found" error. They have to know that `pong` is a placeholder.

**Fix**: replace the placeholder name with one that ships, or one that's unambiguously a placeholder. Two options:

**Option A — point at the scaffold helper:**
```powershell
.EXAMPLE
    # First, scaffold a sandbox to dispatch into:
    pwsh ./tools/scaffold-sandbox.ps1 -Name probe

    # Then dispatch:
    pwsh ./tools/automation/invoke-input-dispatch.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

**Option B — clearly placeholder:**
```powershell
.EXAMPLE
    pwsh ./tools/automation/invoke-input-dispatch.ps1 `
        -ProjectRoot integration-testing/<your-sandbox> `
        -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

Recommend Option A — it teaches the full flow in one step (scaffold → invoke), which is what most agents need. Once pass 2's editor-launch helper exists, also include the launch + stop boundaries in at least one example per script.

For pin/unpin/list, use the same `probe` sandbox in examples.

**How to verify**:
1. `Get-Help tools/automation/invoke-input-dispatch.ps1 -Examples` shows the new `probe`-based example.
2. Copy-paste the entire example block into a fresh shell and run it. With the editor running (post pass-2's `-EnsureEditor`), it should produce a success envelope.
3. Optional: add a Pester test to [InvokeRunbookScripts.Tests.ps1](../tools/tests/InvokeRunbookScripts.Tests.ps1) that scans all `invoke-*.ps1` scripts and asserts every `-ProjectRoot` example value matches an existing path under `integration-testing/`.

---

### L3 — Junction-vs-symlink choice in `check-addon-parse.ps1` is undocumented

**Where**: [tools/check-addon-parse.ps1:67-78](../tools/check-addon-parse.ps1#L67-L78) (creation) and [lines 138-145](../tools/check-addon-parse.ps1#L138-L145) (cleanup).

Current code:

```powershell
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    cmd /c mklink /J "`"$projectAddonLink`"" "`"$addonSource`"" | Out-Null
} else {
    New-Item -ItemType SymbolicLink -Path $projectAddonLink -Target $addonSource | Out-Null
}
```

**Why the special-casing exists** (currently undocumented): on Windows, `New-Item -ItemType SymbolicLink` requires either Developer Mode enabled or running as administrator. `cmd /c mklink /J` (junction) doesn't — junctions are a kind of mount point that any user can create. Junctions only work for directories on the same volume, which is fine for this use case (project and addon both live in the repo).

Cleanup is symmetric: `cmd /c rmdir` removes a junction without deleting the link target; `Remove-Item -Recurse` would delete the target too.

**Symptom (latent)**: a future maintainer reads this code, thinks "why are we shelling out to cmd?", and "simplifies" it to `New-Item -ItemType SymbolicLink`. Now `check-addon-parse.ps1` requires admin or Developer Mode on every contributor's machine. Or they replace `cmd /c rmdir` with `Remove-Item -Recurse -Force`, which wipes the actual addon source under `addons/agent_runtime_harness/` because the junction's target is followed.

**Fix**: add comments explaining the reasoning at both sites. No code change.

```powershell
# Use a directory junction (`mklink /J`) on Windows instead of New-Item -SymbolicLink.
# Junctions don't require Developer Mode or admin elevation, while symlinks do.
# Junctions are restricted to same-volume directories, which is fine here — both the
# repo addon source and the test project live in the repo. On non-Windows we use
# real symlinks (no elevation issue on POSIX).
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    cmd /c mklink /J "`"$projectAddonLink`"" "`"$addonSource`"" | Out-Null
} else {
    New-Item -ItemType SymbolicLink -Path $projectAddonLink -Target $addonSource | Out-Null
}
```

And at the cleanup site:
```powershell
# Junctions on Windows must be removed with `rmdir` (which removes the link entry only).
# Remove-Item -Recurse -Force would follow the junction and delete the actual addon
# source under addons/agent_runtime_harness/ — never use that here.
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    cmd /c rmdir "`"$projectAddonLink`"" | Out-Null
} else {
    Remove-Item -LiteralPath $projectAddonLink -Force
}
```

**How to verify**: this is a doc-only change. Re-run `pwsh ./tools/check-addon-parse.ps1` after the comment is added; behavior is unchanged. Confirm no test regressions: `pwsh ./tools/tests/run-tool-tests.ps1`.

---

### M6 — Fixture `outputDirectory` is a static name across runs

**Where**: every fixture under [tools/tests/fixtures/runbook/](../tools/tests/fixtures/runbook/). Examples:
- `input-dispatch/press-enter.json:6` → `"outputDirectory": "res://evidence/automation/runbook-input-dispatch"`
- `behavior-watch/single-property-window.json:6` → same shape
- `inspect-scene-tree/startup-capture.json:7` → same shape
- etc.

Note: `invoke-scene-inspection.ps1`'s inline payload at [line 151](../tools/automation/invoke-scene-inspection.ps1#L151) DOES use `"res://evidence/automation/$requestId"` (requestId-suffixed). Only the fixtures use static names.

**Symptom**: collisions across runs are prevented only because [Initialize-RunbookTransientZone](../tools/automation/RunbookOrchestration.psm1#L689-L800) wipes `evidence/automation/` before each run. If cleanup is ever bypassed (e.g., a future `-SkipCleanup` flag, or a partial cleanup failure), prior-run evidence at `res://evidence/automation/runbook-input-dispatch/` is silently overwritten by the next run.

Also, the static name makes pinning harder to reason about: if you list `evidence/automation/`, you can't tell which run produced which directory without reading every manifest's `runId` field.

**Fix**: make every fixture's `outputDirectory` requestId-suffixed at runtime. Two options.

**Option A — fixture-level placeholder substitution**: introduce a `$REQUEST_ID` placeholder in fixtures, and have `Resolve-RunbookPayload` substitute it after parsing.

In each fixture:
```json
"outputDirectory": "res://evidence/automation/$REQUEST_ID"
```

In `Resolve-RunbookPayload`, after `$payload['requestId'] = $RequestId` at [line 193](../tools/automation/RunbookOrchestration.psm1#L193):
```powershell
# Substitute $REQUEST_ID placeholders in path-shaped fields.
foreach ($pathField in @('outputDirectory', 'artifactRoot')) {
    if ($payload.ContainsKey($pathField) -and $payload[$pathField] -is [string]) {
        $payload[$pathField] = $payload[$pathField].Replace('$REQUEST_ID', $RequestId)
    }
}
```
(After pass 1's C2, `artifactRoot` is gone — drop the array entry.)

**Option B — orchestrator-side override**: have `Resolve-RunbookPayload` always overwrite `outputDirectory` to `res://evidence/automation/<requestId>`, ignoring whatever the fixture specifies. Treats `outputDirectory` as orchestrator-owned, not fixture-owned. Cleaner contract but loses the ability to override per fixture.

Recommend Option A — keeps fixtures self-documenting, supports edge cases where a fixture wants a non-standard directory layout.

**How to verify**:
1. Update a fixture (e.g. `press-enter.json`) to use `$REQUEST_ID`.
2. Run an invoke script with that fixture; check the request that landed at `harness/automation/requests/run-request.json` (capture before broker consumption with a debug breakpoint, OR replay via the new pass-3 broker-mock tests).
3. `outputDirectory` should be `res://evidence/automation/runbook-input-dispatch-<timestamp>-<rand>`, not `res://evidence/automation/runbook-input-dispatch`.
4. After the run, the actual evidence directory matches the substituted name.

Add a Pester test that calls `Resolve-RunbookPayload` with a fixture containing `$REQUEST_ID` and asserts the substitution happens.

## How to validate the whole pass

### Static checks

```powershell
pwsh ./tools/tests/run-tool-tests.ps1
```

Expectation:
- New L2 test asserting `-ProjectRoot` examples in all `invoke-*.ps1` reference paths under `integration-testing/`.
- New M6 test for `Resolve-RunbookPayload` `$REQUEST_ID` substitution.
- All existing tests pass.

`Get-Help` smoke-test:
```powershell
foreach ($script in (Get-ChildItem ./tools/automation/invoke-*.ps1)) {
    $help = Get-Help $script.FullName -Examples
    "$($script.Name): $($help.Examples.Example.Count) example(s)"
}
```
Every script should have at least one example. Skim them — none should reference `pong`.

### Live integration test

```powershell
# Combined check: scaffolded sandbox + requestId-suffixed evidence dirs.
pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe   # if pass 2 landed

# Run the same workflow twice without cleanup interference.
$r1 = pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json | ConvertFrom-Json

$r2 = pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json | ConvertFrom-Json

# Each manifest should live in a distinct, requestId-suffixed directory.
[System.IO.Path]::GetDirectoryName($r1.manifestPath)
[System.IO.Path]::GetDirectoryName($r2.manifestPath)
# Different paths. Both end with the run's requestId.

pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
```

Note: in normal operation the cleanup wipes `evidence/automation/` between runs, so only the latest is on disk after the second invoke. The "two simultaneous evidence dirs" scenario is what M6 enables for future work (e.g. a `-SkipCleanup` flag, parallel runs against multiple sandboxes).

### Junction comment check

```powershell
pwsh ./tools/check-addon-parse.ps1
```
Should still exit 0. The L3 change is comment-only.

## Out of scope for this pass

- **Pass 1** ([01-unblock-the-loop.md](01-unblock-the-loop.md)): validate-then-rename, drop `artifactRoot`, fix `.TrimEnd()` template leak, strip ANSI. Should land before this pass — M6's `$REQUEST_ID` substitution lives in `Resolve-RunbookPayload`, which pass 1 also touches.
- **Pass 2** ([02-dry-ergonomics.md](02-dry-ergonomics.md)): editor launch helper, scene-inspection refactor, pin/unpin exit codes. Should land before this pass — L2's example refresh references the pass-2 launch helper.
- **Pass 3** ([03-hardening-tests.md](03-hardening-tests.md)): clean `requests/`, mock the broker for CI, surface unclassified-cleanup diagnostics, decouple from hardcoded `pwsh`. Should land before this pass — M6's verification benefits from the broker-mock tests.

Do not introduce a `-SkipCleanup` flag as part of this pass; that's a future feature that M6 makes safe to add later. Do not migrate the example sandbox name to anything except `probe` (matching `scaffold-sandbox.ps1`'s default expectation set in [tools/tests/ScaffoldSandbox.Tests.ps1](../tools/tests/ScaffoldSandbox.Tests.ps1)).
