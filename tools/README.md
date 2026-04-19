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
