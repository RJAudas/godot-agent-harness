# Quickstart: Pin a Run, Reproduce, Compare

**Feature**: 009-evidence-lifecycle | **Plan**: [plan.md](./plan.md)

For agents (and humans) who need to capture a run on purpose and keep it safe across future invocations. Everything below uses documented `invoke-*.ps1` scripts — no hand-authored filesystem commands.

## The three-step pattern

### 1. Run the workflow and read its evidence

Pick the orchestration script that matches what you want to verify and call it once — exactly as you would have before this feature existed:

```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot integration-testing/my-sandbox `
  -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/wall-bounce.json
```

The script now does three things automatically before dispatch (new in this feature):
- Writes an **in-flight marker** into the transient zone so a concurrent second invocation fails fast.
- **Clears** the prior run's transient files (no stale `run-result.json` left to confuse you).
- **Aborts** with a clear failure envelope if cleanup cannot complete — you will never see a mix of old and new files.

Read the stdout envelope. Follow `manifestPath` to the evidence. This is unchanged from the existing runbook.

### 2. Pin the run under a name you choose

You decided the run is worth keeping — e.g., it reproduces a bug. Pin it:

```powershell
pwsh ./tools/automation/invoke-pin-run.ps1 `
  -ProjectRoot integration-testing/my-sandbox `
  -PinName bug-repro-jumpscare
```

This **copies** the current transient zone (the `run-result.json`, `lifecycle-status.json`, and the whole `evidence/<runId>/` subtree referenced by the manifest) into `harness/automation/pinned/bug-repro-jumpscare/`. The stdout envelope (`lifecycle-envelope.schema.json`) reports `operation: "pin"`, the pinned `pinName`, and the full `plannedPaths[]` audit trail.

What you do NOT do:
- Hand-copy files with `Copy-Item` or `Remove-Item`.
- Rename directories by hand.
- Read prior-run artifacts to figure out the `runId` first. The pin script finds it.

If a pin with that name already exists, the script **refuses** with `failureKind: "pin-name-collision"`. Pass `-Force` to overwrite on purpose, or pick a new name.

### 3. Reproduce on a clean slate and compare

Run the workflow again. The transient zone is cleared automatically (step 1's built-in cleanup), but your pinned run is untouched because it lives in the pinned zone, which transient cleanup never reaches:

```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot integration-testing/my-sandbox `
  -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/wall-bounce.json
```

You now have two sets of evidence side by side:

| Pinned (baseline) | Live (new run) |
|---|---|
| `integration-testing/my-sandbox/harness/automation/pinned/bug-repro-jumpscare/evidence/<runId>/evidence-manifest.json` | `integration-testing/my-sandbox/evidence/automation/<new-runId>/evidence-manifest.json` |
| `integration-testing/my-sandbox/harness/automation/pinned/bug-repro-jumpscare/results/run-result.json` | `integration-testing/my-sandbox/harness/automation/results/run-result.json` |

Diff them with whichever tool you already use — the layouts mirror each other deliberately, so `jq`-based or schema-aware comparisons work without path surgery.

## Listing and removing pins

**Enumerate** pinned runs (emits a `pinnedRunIndex[]` matching `contracts/pinned-run-index.schema.json`):

```powershell
pwsh ./tools/automation/invoke-list-pinned-runs.ps1 `
  -ProjectRoot integration-testing/my-sandbox
```

**Remove** a pin you no longer need. Dry-run first to see exactly what would go:

```powershell
pwsh ./tools/automation/invoke-unpin-run.ps1 `
  -ProjectRoot integration-testing/my-sandbox `
  -PinName bug-repro-jumpscare `
  -DryRun
```

If the `plannedPaths[]` output looks right, drop `-DryRun`:

```powershell
pwsh ./tools/automation/invoke-unpin-run.ps1 `
  -ProjectRoot integration-testing/my-sandbox `
  -PinName bug-repro-jumpscare
```

## When NOT to use any of this

- **Don't pin every run.** The orchestration scripts already produce full evidence; the pinned zone is for runs you deliberately want to compare against later. A pin has cost — disk, cognitive overhead, a name to remember.
- **Don't read prior-run artifacts to plan a new run.** Still the rule from [CLAUDE.md](../../CLAUDE.md). If you need to reference a prior run, pin it first, then read the pinned copy — never the transient zone of a run you didn't just dispatch.
- **Don't hand-delete files in the transient zone.** The next orchestration call handles it. There is no supported scenario where an agent needs to run `Remove-Item` against harness output.

## What git sees

After any sequence of runs and pins: nothing. The `.gitignore` rules cover the transient zone, the pinned zone, and the per-run evidence trees across all project locations (including fixture directories that double as runtime targets, per FR-003/FR-004). If `git status` shows a modified or untracked file under `harness/automation/**` or `evidence/automation/**`, that is a bug in this feature — report it.

## Envelope reference

Every script in this quickstart emits JSON on stdout that conforms to `contracts/lifecycle-envelope.schema.json`. The fields you usually care about:

- `status`: `ok` on success, `refused` on precondition failure (name collision, concurrent run in progress), `failed` on unexpected error.
- `failureKind`: enumerated reason when not `ok` — e.g., `pin-name-collision`, `run-in-progress`, `pin-source-missing`.
- `operation`: `cleanup`, `pin`, `unpin`, `list` — a route key for log parsing.
- `plannedPaths[]`: every file the operation touched (or would touch under `-DryRun`). This is your audit trail.
- `pinName` / `pinnedRunIndex`: set when the operation is about pins.
- `diagnostics[]`: surfaced warnings — e.g., "recovered from stale in-flight marker from PID 12345."

No parsing surprises relative to the 008-agent-runbook envelope: `status` / `failureKind` / `diagnostics` / `completedAt` / `manifestPath` all have the same meanings; `manifestPath` is `null` for lifecycle operations (none of them emit a run's evidence).
