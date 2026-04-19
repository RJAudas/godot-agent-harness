# tools/

Repository-local helper scripts. Most scripts emit machine-readable JSON and
accept repository-relative paths so they compose cleanly in CI and agent flows.

## Layout

- `automation/` — autonomous-run brokers, capability lookups, and write-boundary contracts.
- `evals/` — seeded eval prompts, fixtures, and result files.
- `evidence/` — manifest-centered evidence helpers (creation and validation).
- `tests/` — Pester regressions for the PowerShell scripts. Run them with
  `pwsh ./tools/tests/run-tool-tests.ps1`.
- `validate-json.ps1` — generic JSON+JSON-Schema validator used by the other tools.
- `deploy-game-harness.ps1` — copies the harness addon into a target Godot
  project. Use `-AddonOnly` to skip everything except the addon copy when
  the in-editor **Deploy Agent Assets** button will seed the rest.
- `check-addon-parse.ps1` — runs Godot headless against a sandbox project
  and fails when the addon emits parse or compile errors. See below.

## `check-addon-parse.ps1`

Catches GDScript parse and compile errors in the addon without a manual
deploy + editor reload cycle. Opens a minimal fixture project
(`tools/fixtures/addon-parse-check/`) in headless editor mode with the
addon junctioned into its own `addons/` directory, lets Godot parse every
script, then exits.

```pwsh
pwsh ./tools/check-addon-parse.ps1
```

The script needs a Godot 4.x binary. It looks up, in order:

1. `$env:GODOT_BIN` (full path to a Godot executable)
2. `godot`, `godot4`, `Godot_v4`, or `Godot` on `PATH`

### Setting up Godot on PATH (Windows)

1. Download the Godot 4.x **standard** build from
   <https://godotengine.org/download/windows/> and unzip it somewhere stable,
   for example `C:\Tools\Godot\`.
2. Rename the executable to `godot.exe` (optional — keeps the lookup short)
   or leave it as `Godot_v4.6.2-stable_win64.exe` and use `GODOT_BIN`.
3. Add the folder to `PATH` for the current user:
   ```pwsh
   [Environment]::SetEnvironmentVariable(
       'Path',
       "$([Environment]::GetEnvironmentVariable('Path','User'));C:\Tools\Godot",
       'User'
   )
   ```
   Open a new terminal so the change takes effect, then verify with
   `Get-Command godot`.
4. Or, instead of editing `PATH`, point `GODOT_BIN` at the executable:
   ```pwsh
   [Environment]::SetEnvironmentVariable(
       'GODOT_BIN',
       'C:\Tools\Godot\Godot_v4.6.2-stable_win64.exe',
       'User'
   )
   ```

### Setting up Godot on PATH (macOS / Linux)

```bash
# Example: install to /opt/godot and symlink
sudo ln -s /opt/godot/Godot_v4.6.2-stable_linux.x86_64 /usr/local/bin/godot
# Or export GODOT_BIN in your shell profile:
export GODOT_BIN=/opt/godot/Godot_v4.6.2-stable_linux.x86_64
```

### Exit codes

- `0` — no parse or compile errors detected.
- `1` — errors detected (script prints the offending lines) or Godot
  could not be located / timed out.

## End-to-end plugin testing in `integration-testing/`

The repository deliberately does **not** ship a runnable Godot project.
Instead, every developer creates a sandbox project under the git-ignored
`integration-testing/` folder and exercises the full broker → playtest →
evidence loop there. See [`docs/INTEGRATION_TESTING.md`](../docs/INTEGRATION_TESTING.md)
for project-creation guidance; the loop steps below assume you have a
project at `integration-testing/<name>/` with the harness already
deployed via `tools/deploy-game-harness.ps1`.

All commands assume the repo root as the working directory. Replace
`<name>` with your sandbox project name (e.g. `smoke`).

### 1. Parse-check the addon

```pwsh
pwsh ./tools/check-addon-parse.ps1
```

Fix anything it reports before continuing.

### 2. Launch the editor against the sandbox

```pwsh
godot --editor --path integration-testing/<name>
```

If `godot` is not on `PATH` for the current shell, fall back to
`& $env:GODOT_BIN --editor --path integration-testing/<name>`. Do **not**
embed an absolute install path in checked-in scripts or docs — the
parse-check helper resolves the binary the same way and is the
canonical lookup.

When the editor finishes loading with the **Agent Runtime Harness**
plugin enabled, the broker writes
`integration-testing/<name>/harness/automation/results/capability.json`.

### 3. Confirm the capability advertisement

```pwsh
pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot integration-testing/<name>
```

Look for `inputDispatch.supported = true` (and any other capability
flag relevant to the change under test).

### 4. Submit a fixture request

With the editor still open:

```pwsh
pwsh ./tools/automation/request-editor-evidence-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/pong-testbed/harness/automation/requests/run-request.healthy.json
```

Any tracked fixture under `tools/tests/fixtures/pong-testbed/harness/automation/requests/`
can be reused as a request template, or you can author a custom one
inside the sandbox at `integration-testing/<name>/harness/automation/requests/`.
The helper writes the request file the broker watches; the broker
(running inside the editor) launches the playtest and persists evidence.

### 5. Read the results

```pwsh
Get-Content integration-testing/<name>/harness/automation/results/run-result.json |
    ConvertFrom-Json | Format-List
```

Then open the `evidence-manifest.json` it points at and inspect the
referenced artifacts (`input-dispatch-outcomes.jsonl` for input-dispatch
runs).

### 6. Validate the manifest and re-run the regression suite

```pwsh
pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>
pwsh ./tools/tests/run-tool-tests.ps1
```

