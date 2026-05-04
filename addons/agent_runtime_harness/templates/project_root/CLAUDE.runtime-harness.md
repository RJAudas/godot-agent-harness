## Runtime Harness

This project has the `agent_runtime_harness` addon installed. When the user asks to run the game, press keys, verify at runtime, inspect the scene, or watch for errors, delegate to the `godot-runtime-verification` subagent (`.claude/agents/godot-runtime-verification.md`) or follow the fast path below directly.

## Static-first verification

Match verification depth to how much of the fix's correctness is provable from the diff alone, not to the fact that it's a fix. Default to static; reach for runtime tools only when static is insufficient.

**Static reading is sufficient when:**

- Every claim the fix makes is visible in the change itself.
- A **known-good sibling** in the same file shows what "right" looks like — e.g. four platforms with `collision_layer = 1` make the fifth's `0 → 1` self-evident. The working siblings *are* the verification.
- The change is structural (rename, refactor) with no behavioral effect.
- An experienced engineer would approve the PR without running it.

**Runtime verification is appropriate when** the fix's correctness depends on emergent behavior the diff cannot prove:

- **Timing** — frame ordering, signal cascades, race conditions.
- **Async** — callback ordering, awaited operations, concurrent state.
- **Physics tuning** — feel parameters whose right value can only be felt by playing.
- **Integration glue** — cross-system behavior (pause + animation, save + state).
- **Visual / performance** — anything where "does it look right" or "does it run fast enough" is the criterion.
- The first fix attempt didn't land and observation is needed to redirect.

When runtime *is* the right tool, run the **smallest reproduction that yields the evidence you need** — a single scene inspection, one keypress, a short watch window. A full-level playthrough or a perfectly-timed input sequence is the wrong tool when a focused observation would settle the question.

This default is calibrated for current model strength. As model capability and harness features evolve, the static/runtime threshold may move; keeping the rule visible here lets it be retuned without rewriting the template.

## Fast path — one invoke script, one envelope

The runtime invokers all assume a Godot editor is running against the project. Pass `-EnsureEditor` to have them auto-launch one (idempotent: reuses an existing editor when capability.json is fresh).

```powershell
# Scene inspection (no input). -EnsureEditor spawns the editor if needed.
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1 `
  -ProjectRoot "<absolute path to this project>" -EnsureEditor

# Input dispatch (keypresses / InputMap actions)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" -EnsureEditor `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/input-dispatch/press-enter.json"

# Runtime error triage
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot "<absolute path to this project>" -EnsureEditor `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json"

# When you're done with this project, stop the editor:
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-stop-editor.ps1 `
  -ProjectRoot "<absolute path to this project>"
```

Parse stdout JSON: `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`. On success read `manifestPath`, then the one artifact the manifest references. On failure, read `diagnostics[0]` first; see **Common failure modes** below for symptom-to-fix mappings on the recurring ones.

Key identifiers: bare Godot names (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`) — not `KEY_ENTER`. InputMap actions: `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Scene inspection

`invoke-scene-inspection.ps1` captures the running tree, including nodes added at runtime and resolved post-`_ready` properties. For statically-authored scenes you can also read the `.tscn` directly, but only this call shows the live state — runtime-instantiated nodes (pooled enemies, spawned projectiles, runtime-loaded levels), live `processing_state` and group membership, and tree state at a specific moment.

## Build errors

For build errors, try the CLI first (run from the project root, or pass `--path <project>`):

- `godot --check-only` — GDScript parse errors
- `godot --import` — asset import / `.tres` / scene-load errors
- `godot --headless --quit-after 1` — autoload `_ready` failures

Use `{{HARNESS_REPO_ROOT}}/tools/automation/invoke-build-error-triage.ps1` as a fallback when the CLI doesn't reproduce the error or doesn't surface enough detail (engine crashes, multi-file dependency error threading, structured JSON output for downstream consumption). If you find yourself reaching for it routinely, file an issue describing what the CLI missed.

## Common failure modes

The diagnostics are usually self-explanatory; this table is for recognising the recurring ones on sight.

| Symptom | Root cause | Fix |
|---|---|---|
| `target_scene_unspecified` blocked-reason | Neither `targetScene` (in `inspection-run-config.json`) nor `application/run/main_scene` (in `project.godot`) is set | Set one of them to a `res://` path |
| `target_scene_file_not_found` blocked-reason | The configured path doesn't exist on disk | Fix the path; the diagnostic names the offending file |
| `failureKind: "build"` instead of a scene-load failure | The target scene exists but its scripts have parse errors | See **Build errors** above |
| `incompatible_stop_policy` validation rejection | `behaviorWatchRequest`'s `frameCount` exceeds `stopPolicy.minRuntimeFrames` (the playtest would stop before the watch window fills) | The diagnostic spells out the exact `stopPolicy.minRuntimeFrames` value to set |
| `unsupported_property` validation rejection: "Behavior watch property '…' is not in the supported allowlist" | Property name not in the watch allowlist (defined in both `automation-run-request.schema.json` and the runtime `BehaviorWatchRequestValidator`) | The diagnostic enumerates allowed values inline; pick one or expand the allowlist (schema + validator) if you have a real need |
| Invoke-script stdout warnings with `status: pass` in the manifest | Manifest's `outcomes` is the source of truth; the warnings flag a non-fatal disconnect (e.g., trace artifact missing) | Trust the manifest |

## Do not

- **Do not hand-author `run-request.json`** — the invoke scripts own the broker loop.
- **Do not manually delete files** under `harness/automation/results/` or `evidence/automation/` — scripts clear the transient zone automatically before every run.
- **Do not read prior-run artifacts** to plan a new run — the transient zone is wiped before every invocation.
- **Do not read addon source** (`addons/agent_runtime_harness/`).
- **Do not vary capture or stop policies speculatively** — fixture defaults are correct.
- **Do not stop and restart the editor speculatively** — `capability.json` reflects current state, and stale editor state is rarely the cause of failures. Read `harness/automation/results/capability.json`, `run-result.json`, or `lifecycle-status.json` first. Restart only when you've confirmed the issue is editor-cached, not config-driven (or when running a CLI tool that needs exclusive project access, e.g. `godot --headless --import`).
- **Do not invoke runtime tools to confirm a fix you already have high static confidence in.** Re-reading the diff is the verification when every claim it makes is visible there or when a known-good sibling in the same file proves the target shape. See **Static-first verification** above.
- **Do not orchestrate elaborate runtime scenarios** (full-level playthroughs, perfectly-timed jump sequences) **when a focused observation would settle the question.** Run the smallest reproduction that yields the evidence you need.

## Subagents

- `godot-runtime-verification` — drives a fresh run (see `.claude/agents/godot-runtime-verification.md`).
- `godot-evidence-triage` — interprets an existing manifest without starting a new run.
