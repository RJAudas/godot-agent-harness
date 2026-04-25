---
description: Drive a Godot runtime verification from this repository using the runbook invoke scripts. One command, one envelope. Stay on the fast path.
---

## User Input

```text
$ARGUMENTS
```

> **Claude Code users**: every workflow below is also available as a `/godot-*` slash command (`/godot-inspect`, `/godot-press`, `/godot-debug-runtime`, `/godot-debug-build`, `/godot-watch`, `/godot-pin`, `/godot-unpin`, `/godot-pins`). The skill auto-invocation is the preferred path. This prompt remains the canonical guidance for Copilot and other non-Claude tools that don't have skill routing.

## Fast path (for every runtime-visible request)

When the user asks to run the game, press keys, verify at runtime, or watch behaviour:

1. **Match the request to a runbook row in [RUNBOOK.md](../../RUNBOOK.md).** Pick the one `invoke-*.ps1` script that covers the workflow.
2. **Call that script once.** Pass the target project root and (when applicable) a fixture from `tools/tests/fixtures/runbook/<workflow>/`.
3. **Parse the JSON envelope the script emits on stdout** (conforming to `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`). That envelope is the single source of truth for the outcome — `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`.
4. **On success, read `manifestPath`**, then the summary artifact referenced by the manifest. That is your evidence. Do not re-derive anything from earlier runs.

### Canonical invocations

Copy these. The orchestration script handles capability checks, request authoring, schema validation, polling, and manifest reading. You do not author `run-request.json` yourself.

```powershell
# "Run the game and press Enter past the main menu"
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot <game-project-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json

# "Press arrow keys to move the player"
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot <game-project-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-arrow-keys.json

# "Watch a property for drift"
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot <game-project-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/single-property-window.json

# "Capture build errors after a compile"
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
  -ProjectRoot <game-project-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json

# "Run and watch for runtime errors"
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot <game-project-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
```

For an ad-hoc input script that no fixture covers, pass `-RequestJson '<inline JSON>'` to `invoke-input-dispatch.ps1` — see its `.EXAMPLE` block. Key identifiers are bare Godot logical names (`ENTER`, `SPACE`, `LEFT`), not `KEY_*` constants.

## Do not

These are the behaviors that waste runs. Prior agents burned five to ten minutes on each.

- **Do not read prior-run artifacts to plan a new run.** The transient zone (`harness/automation/results/` and `evidence/automation/`) is wiped automatically before every new run. Any file you find there belongs to the *current* run. If you need a prior run, it must have been pinned with `invoke-pin-run.ps1` — use `invoke-list-pinned-runs.ps1` to locate it; do not scan the transient zone for historical data.

<!-- runbook:do-not-read-addon-source -->
- **Do not read addon source** (`addons/agent_runtime_harness/`) to understand the harness protocol. Everything you need is in `RUNBOOK.md`, `.claude/skills/godot-*/SKILL.md`, `specs/008-agent-runbook/contracts/`, and the invoke script's `Get-Help` output.
<!-- /runbook:do-not-read-addon-source -->

- **Do not hand-author `run-request.json`** when an invoke script exists. The scripts exist precisely to replace that step.
- **Do not shell out to generate request IDs, spelunk for example payloads, or construct payloads from raw config files.** The fixture + the invoke script give you a complete payload.
- **Do not vary `capturePolicy`, `stopPolicy`, or event timing speculatively** — the fixture defaults are correct for the common case.

## Routing

- Evidence triage on an existing manifest: hand off to `godot-evidence-triage.prompt.md`. Do not start a new run.
- Pure unit / contract / schema tests with no runtime behavior in scope: run ordinary tests, not the harness.
- Combined validation (runtime-visible change *and* existing deterministic test surface): run both, but do not fabricate a new test suite to satisfy the rule.

## Reading the envelope

The invoke script's stdout JSON contains everything you need to report:

- `status` = `success` or `failure`
- `failureKind` on failure: `editor-not-running`, `timeout`, `request-invalid`, `build`, `runtime`, or `internal`
- `manifestPath` on success — read the manifest next, then one summary artifact
- `diagnostics` array — include these in your report verbatim, especially for build failures (line/column, raw output)
- `outcome` — workflow-specific details (dispatched event count, node count, etc.)

## When the fast path fails

- If the invoke script reports `editor-not-running`, ask the user to launch the editor against the target project root. Do not try to launch it yourself.
- If it reports `timeout`, the broker did not pick up the request. Note: the plugin only processes requests while the game is in play mode — the user may need to press Play.
- If it reports `request-invalid`, the script's diagnostic will name the schema violation. Fix the fixture or the inline payload and rerun.
- If it reports `build`, report the diagnostic entries (`resourcePath`, `message`, `line`, `column`) and the relevant `rawBuildOutput` lines verbatim. Do not paraphrase.

## Output

- Selected workflow (which invoke script)
- The envelope's `status` + `failureKind` (on failure)
- Manifest path and one-line runtime summary on success
- Whether any ordinary tests were also required
- Next concrete debugging step
