# Integration testing in `integration-testing/`

The repository ships **no runnable Godot project**. The Pester regression
suite uses tracked JSON fixtures under
[`tools/tests/fixtures/pong-testbed/`](../tools/tests/fixtures/pong-testbed/),
which need no Godot install. For end-to-end work that requires a real
running editor — manual feature validation, broker smoke tests, evidence
manifest reproduction, agent-side playtest reviews — create a sandbox
project under the git-ignored `integration-testing/` folder.

`integration-testing/` is whitelisted in `.gitignore`: anything inside it
stays local to your machine. Multiple sub-projects can coexist
(`integration-testing/smoke/`, `integration-testing/issue-12-repro/`,
…). Delete a folder when you're done with it.

## Why a local sandbox instead of a tracked example

- **Godot rewrites `project.godot`** on every editor launch (preferences,
  recent files, addon enablement). A committed project would churn on
  every contributor's machine.
- **`.godot/` and `.import/`** are machine-specific caches.
- **Addon-path constraints**: Godot 4.6+ rejects `res://../..` paths, so
  a tracked example has to either duplicate the addon or rely on a
  per-machine junction. Both are fragile.
- A per-developer sandbox keeps the repo free of editor state while
  letting everyone run real broker loops.

## Create a sandbox project

You only need a minimal Godot project (one `project.godot` and one
scene). You can either let Godot scaffold it for you or write the files
by hand.

### Option A — Godot Project Manager (recommended for humans)

1. Open the Godot Project Manager.
2. Click **New Project**.
3. Set **Project Path** to `D:\dev\godot-agent-harness\integration-testing\<name>`
   (use the absolute path; Godot will create the folder).
4. Choose any **Renderer** (Forward+ is fine).
5. Click **Create & Edit**. Godot writes `project.godot` and an empty
   scene. Close the editor immediately — we don't want it to enable any
   plugins until the harness is deployed.

### Option B — Minimal files (recommended for agents)

```pwsh
$proj = 'integration-testing/smoke'
New-Item -ItemType Directory -Path $proj -Force | Out-Null
@'
; Engine configuration file.
config_version=5

[application]

config/name="Integration Sandbox"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.6")
'@ | Set-Content -LiteralPath (Join-Path $proj 'project.godot') -NoNewline

@'
[gd_scene format=3]

[node name="Main" type="Node2D"]
'@ | Set-Content -LiteralPath (Join-Path $proj 'main.tscn') -NoNewline
```

Either option leaves you with a runnable, harness-free Godot project at
`integration-testing/<name>/`.

## Deploy the harness

```pwsh
pwsh ./tools/deploy-game-harness.ps1 -GameRoot integration-testing/<name>
```

This copies the addon, the `harness/` config tree, the `evidence/`
output directory, the agent prompt/agent assets under `.github/`, and
the managed AGENTS.md / `.github/copilot-instructions.md` blocks. Use
`-AddonOnly` if you've already deployed the assets and only want to
refresh the addon code.

After deploy, parse-check the addon:

```pwsh
pwsh ./tools/check-addon-parse.ps1
```

Fix any reported errors before launching the editor — they will block
the broker from starting.

## Run the broker → playtest → evidence loop

The full step-by-step loop (launch editor, read capability, submit
request, read results, validate manifest) lives in
[`tools/README.md`](../tools/README.md#end-to-end-plugin-testing-in-integration-testing).
Use `integration-testing/<name>` as the `-ProjectRoot` for every helper
invocation.

For agent-driven workflows, prefer the parameterized orchestration scripts
(`tools/automation/invoke-*.ps1`). See [`RUNBOOK.md`](../RUNBOOK.md) for
the quick-reference index of scripts, fixture templates, and recipe docs.

## Cleanup

```pwsh
Remove-Item -Recurse -Force integration-testing/<name>
```

The directory is git-ignored; nothing else needs to happen.
