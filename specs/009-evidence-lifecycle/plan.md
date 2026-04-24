# Implementation Plan: Run-Artifact Evidence Lifecycle

**Branch**: `009-evidence-lifecycle` | **Date**: 2026-04-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-evidence-lifecycle/spec.md`

## Summary

Introduce a declared **lifecycle** for every file the harness writes into a target project: a **transient zone** that is wiped and serialized before every new run, a **pinned zone** that preserves deliberately-kept runs, and a **git-hygiene** pass that stops the fixture tree from accidentally tracking runtime output. The feature is delivered at the PowerShell orchestration layer (per FR-011): extending `RunbookOrchestration.psm1`, adding three new `invoke-*.ps1` scripts for pin/unpin/list, updating `.gitignore`, purging the 13 accidentally-tracked files under `tools/tests/fixtures/pong-testbed/evidence/`, and synchronizing the agent-facing docs. No Godot editor, autoload, debugger, or GDExtension surface changes are required — the addon continues to write through its existing artifact-store interfaces. The one new machine-readable artifact introduced is the **pinned-run index** (enumeration output); all other agent reads remain the existing `evidence-manifest.json` + workflow artifacts.

## Technical Context

**Language/Version**: PowerShell 7 (pwsh) for orchestration/cleanup/pin scripts; no GDScript changes expected.
**Primary Dependencies**: Existing `tools/automation/RunbookOrchestration.psm1` module (from 008); existing `tools/validate-json.ps1`; Pester 5 (test harness already in repo).
**Storage**: JSON/JSONL files inside each target project's working tree — `harness/automation/results/` (transient) and a new `harness/automation/pinned/<pin-name>/` (pinned). No database, no repo-level store.
**Testing**: Pester unit tests against orchestration module + integration tests in `.tmp/` sandbox proving two back-to-back runs produce no field bleed-through; a CI-runnable check asserting `git status --porcelain` stays empty after canonical invocations; schema validation via `tools/validate-json.ps1` for the new pinned-run index and cleanup envelopes.
**Target Platform**: pwsh 7 on Windows (primary, matches CI); scripts remain portable to macOS/Linux pwsh where the existing scripts already run.
**Project Type**: PowerShell tooling + agent-facing documentation update. No new addon code.
**Performance Goals**: Pre-run cleanup MUST complete in well under the existing capability-freshness window (300s). Target: ≤ 500 ms for a transient zone with typical artifact counts (< 50 small JSON/JSONL files).
**Constraints**: Plugin-first preserved (FR-011 — no new Godot extension points); machine-readable envelopes compatible with `orchestration-stdout.schema.json`; no silent partial cleanup (FR-010); no writes outside declared zones (FR-009).
**Scale/Scope**: Extends every existing orchestration script (5 scripts from 008: input-dispatch, scene-inspection, behavior-watch, build-error-triage, runtime-error-triage), adds 3 new scripts (pin/unpin/list), updates `.gitignore` and ~7 doc files, removes 14 tracked fixture files, and adds Pester coverage for the new paths.

## Reference Inputs

- **Internal Docs**:
  - [CLAUDE.md](../../CLAUDE.md) — "Do not read prior-run artifacts to plan a new run" and the transient-zone layout.
  - [AGENTS.md](../../AGENTS.md) — validation routing and write-boundary guidance.
  - [RUNBOOK.md](../../RUNBOOK.md) — workflow-to-script mapping; pin/unpin/list rows will be added.
  - [docs/INTEGRATION_TESTING.md](../../docs/INTEGRATION_TESTING.md) — existing `integration-testing/*` git-ignore convention this feature extends.
  - [docs/AGENT_RUNTIME_HARNESS.md](../../docs/AGENT_RUNTIME_HARNESS.md) — harness architecture context.
  - [docs/AI_TOOLING_BEST_PRACTICES.md](../../docs/AI_TOOLING_BEST_PRACTICES.md) — agent-tooling conventions.
  - [docs/GODOT_PLUGIN_REFERENCES.md](../../docs/GODOT_PLUGIN_REFERENCES.md) — required citation target per Constitution §II (consulted; no new Godot API surface touched).
  - [docs/runbook/](../../docs/runbook/) — existing recipes (`input-dispatch.md`, `inspect-scene-tree.md`, `behavior-watch.md`, `build-error-triage.md`, `runtime-error-triage.md`) that must reference the new lifecycle behavior.
  - [specs/008-agent-runbook/plan.md](../008-agent-runbook/plan.md) — style template and the script pattern this plan extends.
  - [specs/008-agent-runbook/contracts/orchestration-stdout.schema.json](../008-agent-runbook/contracts/orchestration-stdout.schema.json) — envelope schema the new scripts must remain compatible with.
  - [specs/003-editor-evidence-loop/contracts/](../003-editor-evidence-loop/contracts/) — `automation-run-result.schema.json`, `automation-lifecycle-status.schema.json`, `automation-capability.schema.json` — transient-zone payload shapes.
  - [specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json](../001-agent-tooling-foundation/contracts/evidence-manifest.schema.json) — the manifest the pinned-run index references.
  - [tools/automation/write-boundaries.json](../../tools/automation/write-boundaries.json) + [tools/automation/write-boundaries.schema.json](../../tools/automation/write-boundaries.schema.json) — declarative write-zone mechanism that will gain entries for the transient and pinned zones.
  - [tools/README.md](../../tools/README.md) — tool inventory; new scripts must be listed here.

- **External Docs**:
  - [Godot — Project file system](https://docs.godotengine.org/en/stable/tutorials/editor/project_manager.html) — per-project file layout expectations.
  - [Git — gitignore pattern format](https://git-scm.com/docs/gitignore) — pattern precedence for the fixture-tree `evidence/**` rule.
  - [PowerShell — `Remove-Item -LiteralPath`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/remove-item) — safe-delete idioms referenced in the research phase for Windows file-lock behavior.

- **Source References**:
  - `addons/agent_runtime_harness/editor/ScenegraphAutomationArtifactStore.gd` — writes `harness/automation/results/*.json`. Inspected read-only; no changes planned.
  - `addons/agent_runtime_harness/runtime/ScenegraphArtifactWriter.gd` — writes `evidence/automation/<run-id>/evidence-manifest.json`. Inspected read-only; no changes planned.
  - `tools/automation/RunbookOrchestration.psm1` — orchestration module that will gain `Initialize-RunbookTransientZone`, `Assert-NoInFlightRun`, and the pin/unpin/list helpers.
  - `tools/automation/invoke-*.ps1` — existing orchestration entry points; each gains a pre-run cleanup + in-flight-marker call.
  - `tools/tests/InvokeRunbookScripts.Tests.ps1` — Pester suite that must grow coverage for the new behaviors.
  - `tools/tests/fixtures/pong-testbed/evidence/**` and `tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json` — the 14 accidentally-tracked files to purge per FR-004.
  - `../godot` checkout (repository-sibling) — consulted per Constitution §II; no engine-level read required for this feature.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Plugin-first approach preserved**: The plan is pure PowerShell + `.gitignore` + docs. Per FR-011, no addon, autoload, debugger, or GDExtension surface is introduced or modified. The addon continues to emit `run-result.json` / `evidence-manifest.json` through its existing `ScenegraphAutomationArtifactStore` and `ScenegraphArtifactWriter` classes.
- [x] **Reference coverage complete**: Each Technical Context claim has a citation in Reference Inputs; the pong-testbed and .gitignore facts are grounded in concrete paths enumerated above; the 008-agent-runbook plan is the style template.
- [x] **Runtime evidence defined**: Existing `evidence-manifest.json` and workflow-specific artifacts remain authoritative. The one new machine-readable artifact is the **pinned-run index** returned by the list operation; its contract goes in `contracts/pinned-run-index.schema.json` (Phase 1). Cleanup/pin/unpin/list operations emit stdout envelopes compatible with (or an explicit extension of) `orchestration-stdout.schema.json`.
- [x] **Test loop defined**: US1 → back-to-back `invoke-*.ps1` Pester test asserting zero first-run-field bleed-through. US2 → CI-runnable `git status --porcelain` check after canonical invocations. US3 → pin-and-rerun test asserting pinned-run bytes unchanged across a cleanup cycle. US4 → documentation static-check test (no ad-hoc deletions in recipes) + dry-run envelope test.
- [x] **Reuse justified**: We extend `RunbookOrchestration.psm1` (new functions, same module) rather than adding a parallel module. The in-flight marker is a plain JSON file in the existing transient zone, not a new IPC mechanism. The pinned zone uses the same per-project layout the harness already assumes. No new frameworks; no recreation of Godot debug facilities.
- [x] **Documentation synchronization planned**: Phase 2 tasks will update [RUNBOOK.md](../../RUNBOOK.md), [AGENTS.md](../../AGENTS.md), [CLAUDE.md](../../CLAUDE.md), [docs/INTEGRATION_TESTING.md](../../docs/INTEGRATION_TESTING.md), [docs/AGENT_RUNTIME_HARNESS.md](../../docs/AGENT_RUNTIME_HARNESS.md), [tools/README.md](../../tools/README.md), each file in [docs/runbook/](../../docs/runbook/), [.github/copilot-instructions.md](../../.github/copilot-instructions.md), and the relevant `.github/instructions/*.md` / `.github/prompts/*.md` / `.github/agents/*.md` files that reference harness output. [addons/agent_runtime_harness/templates/project_root/](../../addons/agent_runtime_harness/templates/project_root/) gets an updated `.gitignore` fragment so deployed projects inherit the hygiene rules out-of-the-box.
- [x] **Addon parse-check planned**: No GDScript edits are expected. If implementation discovers a runtime-side change is required (e.g., addon starts refusing to write into a missing directory and needs a guard), the tasks file will require `pwsh ./tools/check-addon-parse.ps1` as a prerequisite; a non-zero exit blocks the task. The default assumption remains: this feature does not touch addon GDScript.

## Project Structure

### Documentation (this feature)

```text
specs/009-evidence-lifecycle/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (cleanup atomicity, marker format, index schema)
├── data-model.md        # Phase 1 output (zones, entities, transitions)
├── quickstart.md        # Phase 1 output (agent-facing "pin + rerun" walk-through)
├── contracts/           # Phase 1 output:
│   ├── pinned-run-index.schema.json
│   ├── in-flight-marker.schema.json
│   └── lifecycle-envelope.schema.json
├── checklists/
│   └── requirements.md  # Already present from /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT created by /speckit.plan)
```

### Source Code (repository root — files this feature touches)

```text
tools/
├── automation/
│   ├── RunbookOrchestration.psm1        # EDIT: +Initialize-RunbookTransientZone,
│   │                                    #       +Assert-NoInFlightRun,
│   │                                    #       +New-RunbookInFlightMarker,
│   │                                    #       +Clear-RunbookInFlightMarker,
│   │                                    #       +Copy-RunToPinnedZone,
│   │                                    #       +Remove-PinnedRun,
│   │                                    #       +Get-PinnedRunIndex
│   ├── invoke-input-dispatch.ps1        # EDIT: wire pre-run cleanup + marker
│   ├── invoke-scene-inspection.ps1      # EDIT: same
│   ├── invoke-behavior-watch.ps1        # EDIT: same
│   ├── invoke-build-error-triage.ps1    # EDIT: same
│   ├── invoke-runtime-error-triage.ps1  # EDIT: same
│   ├── invoke-pin-run.ps1               # NEW: pin operation (FR-005)
│   ├── invoke-unpin-run.ps1             # NEW: unpin operation (FR-007)
│   ├── invoke-list-pinned-runs.ps1      # NEW: list operation (FR-006)
│   ├── write-boundaries.json            # EDIT: +entries for transient/pinned zones
│   └── write-boundaries.schema.json     # (unchanged)
└── tests/
    ├── InvokeRunbookScripts.Tests.ps1   # EDIT: +stale-file, +in-flight, +git-clean
    └── EvidenceLifecycle.Tests.ps1      # NEW: pin/unpin/list coverage + dry-run

.gitignore                                 # EDIT: add fixture-tree evidence/** +
                                          # harness/automation/results/** +
                                          # harness/automation/pinned/** rules

tools/tests/fixtures/pong-testbed/
├── evidence/…                           # REMOVE: 13 tracked run artifacts (FR-004)
└── harness/expected-evidence-manifest.json  # REMOVE (also run-produced)

addons/agent_runtime_harness/templates/project_root/
└── .gitignore                           # EDIT: carry the new rules into deployed projects

docs/
├── INTEGRATION_TESTING.md               # EDIT: explain zones and pinning
├── AGENT_RUNTIME_HARNESS.md             # EDIT: note evidence lifecycle
└── runbook/
    ├── README.md                         # EDIT: +pin/unpin/list rows
    ├── input-dispatch.md                 # EDIT: note automatic cleanup
    ├── inspect-scene-tree.md             # EDIT: same
    ├── behavior-watch.md                 # EDIT: same
    ├── build-error-triage.md             # EDIT: same
    ├── runtime-error-triage.md           # EDIT: same
    ├── pin-run.md                        # NEW: pin-a-run recipe
    ├── unpin-run.md                      # NEW: unpin recipe
    └── list-pinned-runs.md               # NEW: list recipe

AGENTS.md                                  # EDIT: zones + lifecycle rules
CLAUDE.md                                  # EDIT: fast-path summary of the above
RUNBOOK.md                                 # EDIT: +pin/unpin/list rows
tools/README.md                            # EDIT: +3 new scripts

.github/
├── copilot-instructions.md              # EDIT: mention automatic cleanup + pin ops
├── instructions/tools.instructions.md   # EDIT: same
├── instructions/integration-testing.instructions.md  # EDIT: same
├── prompts/godot-runtime-verification.prompt.md     # EDIT: reinforce no-stale-read
└── agents/godot-evidence-triage.agent.md            # EDIT: mention pinned-run comparison
```

**Structure Decision**: The feature sits entirely in `tools/` (orchestration and tests), `docs/` (recipes), agent-facing surfaces in the repo root, and `.gitignore` / the template project's `.gitignore`. No new top-level directories are introduced. The pinned zone (runtime-visible) is a new **convention** inside each target project at `harness/automation/pinned/<pin-name>/` — it is created by the pin operation on demand and is not a new path in this repository itself. Existing repository paths are sufficient for all code and doc deliverables.

## Complexity Tracking

> No Constitution Check violations to justify. This feature stays entirely within supported PowerShell orchestration and documentation layers; no escalation to GDExtension, debugger-plugin internals, or engine changes is needed.

## Phase 0 — Outline & Research (Output: `research.md`)

Unknowns to resolve before design, each a short research task with a concrete decision + rationale + alternatives:

1. **Atomic transient-zone cleanup on Windows.** Investigate whether `Remove-Item -Recurse` on files held by a recently-exited editor process can race, and settle the pattern (e.g., try-delete-then-rename-on-failure vs enumerate-then-delete). Cite PowerShell docs, existing repo patterns in `RunbookOrchestration.psm1`.
2. **In-flight marker format.** Decide the exact marker filename, location (under `harness/automation/results/`), schema (`requestId`, `pid`, `startedAt`, `invokeScript`), and staleness check (process-alive check via `Get-Process -Id` + timestamp horizon; fallback when PID has been reused). Cite marker-file idioms used elsewhere in the repo (e.g., `harness/automation/requests/` layout).
3. **Pinned zone path convention.** Inside the target project: `harness/automation/pinned/<pin-name>/` with subdirs mirroring the live layout (`evidence/<runId>/…` + `results/run-result.json` + `results/lifecycle-status.json`). Alternative: flatten into a single per-pin directory. Pick and justify.
4. **`.gitignore` pattern precedence.** Confirm that ignoring `**/evidence/automation/**` + `**/harness/automation/results/**` + `**/harness/automation/pinned/**` without accidentally excluding the Pester-oracle files under `tools/tests/fixtures/pong-testbed/harness/automation/results/*.expected.json` is expressible with standard gitignore rules (likely via `!**/*.expected.json` re-include). Produce the exact rule set.
5. **Dry-run envelope format.** Decide whether the dry-run output extends `orchestration-stdout.schema.json` with a new `dryRun: true` + `plannedPaths[]` field, or is a distinct schema. Pick the less disruptive option.
6. **Pinned-run index schema.** Define minimal fields: `pinName`, `manifestPath`, `scenarioId`, `runId`, `pinnedAt`, `status`. Cite the `evidence-manifest.schema.json` fields that populate these.

**Output**: `research.md` with one numbered decision block per topic above, each using the Decision / Rationale / Alternatives template.

## Phase 1 — Design & Contracts (Outputs: `data-model.md`, `contracts/*.schema.json`, `quickstart.md`, agent context)

1. **`data-model.md`** — Entities and state transitions:
   - **Transient zone** (path convention, contents, ownership, lifecycle: `empty → in-flight → complete → cleared-before-next-run`).
   - **In-flight marker** (fields, creation, clearing, staleness recovery path).
   - **Pinned zone** (path convention, ownership, immutability).
   - **Pinned run** (copy invariant, referenced-artifact graph).
   - **Pinned-run index** (generation, fields, consumers).
   - **Run-zone classification table** mapping every artifact name the harness writes to its zone (transient | pinned | oracle | none). This table is the single documented classification location required by FR-001.

2. **Contracts** under `specs/009-evidence-lifecycle/contracts/`:
   - `in-flight-marker.schema.json` — marker file shape (required: `requestId`, `pid`, `startedAt`, `invokeScript`; optional: `hostname`, `toolVersion`).
   - `pinned-run-index.schema.json` — array of pin records with `pinName`, `manifestPath`, `scenarioId`, `runId`, `pinnedAt`, `status`.
   - `lifecycle-envelope.schema.json` — stdout envelope for cleanup/pin/unpin/list operations. Either imports `orchestration-stdout.schema.json` via `$ref` + adds `operation` / `dryRun` / `affectedPaths[]`, or is a sibling schema with a shared common core. Decision recorded in research.md §5.

3. **`quickstart.md`** — A ≤ 2-page agent-facing walk-through covering: "run the game, pin the result, run again, compare" — using exact script invocations and fixture paths. Mirrors the style of `specs/008-agent-runbook/quickstart.md`. This quickstart is the single place the runbook recipes link to for the "compare against a baseline" pattern.

4. **Agent context update** — Replace the plan reference between the `<!-- SPECKIT START -->` and `<!-- SPECKIT END -->` markers in [CLAUDE.md](../../CLAUDE.md) to point to this plan (absolute-to-relative: `specs/009-evidence-lifecycle/plan.md`). Note: broader CLAUDE.md edits (zone concept summary) are Phase 2 documentation tasks, not the marker-region swap.

**Post-design Constitution re-check**: Unchanged from the pre-design check above — no new violations surfaced by the research or contract decisions. Plugin-first remains intact (pure PowerShell + docs + gitignore), evidence surfaces are machine-readable (marker schema, pinned-run index, lifecycle envelope), reuse is justified (single module extended), and the documentation-synchronization set grows by two deployable targets (`templates/project_root/.gitignore` and the three new `docs/runbook/*.md` recipes) — both enumerated in Project Structure above.
