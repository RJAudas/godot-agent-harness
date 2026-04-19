---
applyTo: "integration-testing/**"
---

# Integration Testing Instructions

`integration-testing/` is the git-ignored sandbox for end-to-end runs that need a real Godot editor (manual feature validation, broker smoke tests, evidence reproduction, input-dispatch verification).

- Read `docs/INTEGRATION_TESTING.md` and the "End-to-end plugin testing" section of `tools/README.md` BEFORE creating or modifying anything here.
- Each sandbox lives at `integration-testing/<name>/`. Multiple sandboxes can coexist. Delete a folder when you're done with it; nothing inside the directory is tracked.
- Scaffold the project with the minimal files documented in `docs/INTEGRATION_TESTING.md` (Option B), then run `pwsh ./tools/deploy-game-harness.ps1 -GameRoot integration-testing/<name>` to install the addon, harness config, evidence directory, and managed agent assets. Use `-AddonOnly` to refresh just the addon code on later iterations.
- After any deploy or addon edit, run `pwsh ./tools/check-addon-parse.ps1`. A non-zero exit is a blocking failure that MUST be resolved before launching the editor.
- Resolve the Godot binary exactly the way the parse-check helper does: `$env:GODOT_BIN` first, then `godot`/`godot4`/`Godot*` on `PATH`. If neither resolves in the current shell, check the User-scope environment (`[System.Environment]::GetEnvironmentVariable('GODOT_BIN','User')` and the User `Path` for a `Godot*` directory) before concluding Godot is missing. Do NOT download or extract a Godot binary into the repo, and do NOT hard-code an install path in checked-in scripts or docs.
- Drive the broker loop through the documented helpers: launch the editor against the sandbox, then `pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot integration-testing/<name>`, `pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot integration-testing/<name> -RequestFixturePath <fixture>`, read `harness/automation/results/run-result.json`, then validate the referenced manifest with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`.
- Reuse tracked request fixtures from `tools/tests/fixtures/pong-testbed/harness/automation/requests/` as templates whenever possible. Author sandbox-only request files under `integration-testing/<name>/harness/automation/requests/`; do not commit them.
- Do not commit anything under `integration-testing/`. The folder is whitelisted in `.gitignore` for a reason: Godot rewrites `project.godot` and `.godot/`/`.import/` are machine-specific.
