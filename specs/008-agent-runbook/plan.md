# Implementation Plan: Agent Runbook & Parameterized Harness Scripts

**Branch**: `008-agent-runbook` | **Date**: 2026-04-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-agent-runbook/spec.md`

## Summary

Eliminate the schema-discovery and orchestration tax that stalls coding agents
when they call the harness. Deliver (a) a top-level `RUNBOOK.md` index plus
per-workflow recipes under `docs/runbook/` covering all five existing
harness workflows (scene-graph inspection, build-error reporting,
runtime-error reporting, input dispatch, behavior-watch sampling),
(b) tracked, schema-valid request-fixture templates under
`tools/tests/fixtures/runbook/`, and (c) parameterized PowerShell
orchestration scripts under `tools/automation/invoke-*.ps1` that wrap
`get-editor-evidence-capability.ps1 → request-editor-evidence-run.ps1 →
poll run-result.json → read manifest → read outcomes` into single,
well-documented invocations with a stable stdout JSON contract.

This is pure **repo-side tooling and documentation**: no new addon code,
no engine changes, no new low-level harness contracts. The runtime
evidence consumed (manifests, scene tree JSON, input-dispatch outcomes
JSONL, behavior-watch samples, build / runtime error records) is the
existing evidence-bundle output from prior specs (002, 004, 005, 006,
007). The orchestration scripts merely surface those existing artifacts'
paths in a stable stdout JSON envelope so a future MCP server can wrap
them without rework.

## Technical Context

**Language/Version**: PowerShell 7+ (`pwsh`) for orchestration scripts;
Markdown for the runbook; JSON for fixture templates. No new GDScript.
**Primary Dependencies**: Existing repo helpers —
`tools/automation/get-editor-evidence-capability.ps1`,
`tools/automation/request-editor-evidence-run.ps1`,
`tools/evidence/validate-evidence-manifest.ps1`,
`tools/evidence/artifact-registry.ps1`. Pester 5+ for tests (already used).
**Storage**: Tracked Markdown under `docs/runbook/`; tracked JSON fixtures
under `tools/tests/fixtures/runbook/`; tracked PowerShell under
`tools/automation/`. No runtime persistence introduced by this feature.
**Testing**: Pester suite via `pwsh ./tools/tests/run-tool-tests.ps1`,
extended with new `*.Tests.ps1` files exercising each orchestration
script's parameter contract, editor-not-running failure path, and stdout
JSON shape using mocked helper invocations (no live editor required).
**Target Platform**: PowerShell 7+ on Windows / macOS / Linux developer
shells; no editor required to run the test suite.
**Project Type**: Repo-side tooling and documentation. No editor addon
changes, no autoload changes, no GDExtension.
**Performance Goals**: Orchestration scripts add negligible overhead to
the existing helper invocations (target ≤200 ms wall-clock overhead per
invocation, dominated by capability check + result read); end-to-end
default timeout 60 s as set in spec FR-006.
**Constraints**: Plugin-first (this feature does not touch the plugin
layer at all — it sits above it); machine-readable stdout JSON contract
per script; no interactive prompts (FR-009); reuse existing helpers
rather than reimplement (FR-010); MCP-friendly parameter shapes (FR-009).
**Scale/Scope**: One top-level `RUNBOOK.md`, five recipe files, ~6–10
fixture templates (≥3 input-dispatch + 1 behavior-watch + 1 scene-tree
+ optional build/runtime triage examples), five orchestration scripts
(one per workflow), plus updated prompts under `.github/prompts/` and
`.github/agents/` per FR-012, plus accompanying Pester tests.

## Reference Inputs

- **Internal Docs**:
  - [`RUNTIME_VERIFICATION_AGENT_UX.md`](../../RUNTIME_VERIFICATION_AGENT_UX.md) — captured stall trace and the phased plan this feature implements (Phases 1+2 across all workflows).
  - [`docs/INTEGRATION_TESTING.md`](../../docs/INTEGRATION_TESTING.md) — the end-to-end loop the new recipes condense.
  - [`docs/AGENT_RUNTIME_HARNESS.md`](../../docs/AGENT_RUNTIME_HARNESS.md) — harness architecture and evidence contract overview.
  - [`docs/AI_TOOLING_BEST_PRACTICES.md`](../../docs/AI_TOOLING_BEST_PRACTICES.md) — agent-tooling conventions to follow when adding the new prompts/recipes.
  - [`tools/README.md`](../../tools/README.md) — current tool inventory and the canonical Godot-binary resolution rules to mirror.
  - [`.github/copilot-instructions.md`](../../.github/copilot-instructions.md), [`AGENTS.md`](../../AGENTS.md), [`.github/instructions/tools.instructions.md`](../../.github/instructions/tools.instructions.md), [`.github/instructions/integration-testing.instructions.md`](../../.github/instructions/integration-testing.instructions.md) — agent-facing surfaces that must be updated to reference the new runbook (FR-012, Constitution Principle VI).
  - [`.github/prompts/godot-runtime-verification.prompt.md`](../../.github/prompts/godot-runtime-verification.prompt.md), [`.github/agents/godot-evidence-triage.agent.md`](../../.github/agents/godot-evidence-triage.agent.md) — prompts to be retargeted to the runbook plus the "do not source-spelunk" rule.
  - Schema sources of truth (fixture templates derive from these):
    [`specs/006-input-dispatch/contracts/`](../006-input-dispatch/contracts/),
    [`specs/005-behavior-watch-sampling/contracts/`](../005-behavior-watch-sampling/contracts/) (where applicable; behavior-watch payload is currently part of the run request),
    [`specs/004-report-build-errors/contracts/`](../004-report-build-errors/contracts/),
    [`specs/007-report-runtime-errors/contracts/`](../007-report-runtime-errors/contracts/),
    [`specs/002-inspect-scene-tree/contracts/`](../002-inspect-scene-tree/contracts/).
  - [`tools/tests/fixtures/pong-testbed/harness/automation/requests/`](../../tools/tests/fixtures/pong-testbed/harness/automation/requests/) — existing tracked request fixtures whose shape the new templates mirror.
- **External Docs**: None required. This feature ships no new runtime behavior; all referenced behavior is defined by prior repo specs.
- **Source References**: None required. No engine internals are touched; the `../godot` reference checkout is not consulted by this feature.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Plugin-first approach preserved**: This feature ships zero addon, autoload, debugger, or GDExtension code. It sits strictly above the plugin layer, wrapping existing repo-side PowerShell helpers and adding documentation. Engine extension layers were not considered because there is nothing to extend — the runtime side already works; the failure mode is purely agent-side.
- [x] **Reference coverage complete**: Every important decision is cited in *Reference Inputs* above (stall trace + phased plan from `RUNTIME_VERIFICATION_AGENT_UX.md`; helper-resolution rules from `tools/README.md`; schema sources of truth from per-spec `contracts/` directories; existing fixture shape from the pong-testbed tree).
- [x] **Runtime evidence defined**: This feature does not produce *new* runtime artifacts. It surfaces and documents the existing evidence-bundle outputs (manifest, scene-tree JSON, input-dispatch outcomes JSONL, behavior-watch samples, build/runtime error records). The orchestration scripts emit a *stable stdout JSON envelope* (see `contracts/orchestration-stdout.schema.json`, Phase 1) that contains pointers to those existing artifacts so agents can read them directly.
- [x] **Test loop defined**: Each user story has a concrete test loop. P1 stories (input dispatch, scene inspection) and P2 (failure surfacing) are validated by Pester tests covering parameter contract, editor-not-running failure path, build/runtime/timeout failure classification, and stdout JSON shape — all exercisable with mocked helper invocations and no live editor. P3 (behavior watch) is similarly covered. SC-005 (every recipe has a working invocation + fixture pointer) and SC-002 (no recipe text references addon source paths outside an explicit "do not read" callout) are enforced as static checks in the same Pester suite.
- [x] **Reuse justified**: No new abstractions are introduced. Each orchestration script is a thin wrapper over existing scripts (`get-editor-evidence-capability.ps1`, `request-editor-evidence-run.ps1`, `validate-evidence-manifest.ps1`). The fixture templates reuse the JSON shape already in `tools/tests/fixtures/pong-testbed/harness/automation/requests/`. The Godot-binary and repo-root resolution helpers are reused verbatim from existing scripts (FR-010).
- [x] **Documentation synchronization planned**: Per Constitution Principle VI, this feature *is* a documentation feature, so the doc-sync surface is large and explicit:
  - `RUNBOOK.md` (new, top-level index)
  - `docs/runbook/<workflow>.md` (5 new files)
  - `docs/INTEGRATION_TESTING.md` (add a "see also: RUNBOOK.md" pointer; do not duplicate)
  - `tools/README.md` (add the new `invoke-*.ps1` scripts to the inventory; link to runbook for usage)
  - `.github/copilot-instructions.md` (validation commands list updated to reference the new orchestration scripts; routing rules unchanged)
  - `AGENTS.md` (validation expectations updated to point at the new scripts and the runbook)
  - `.github/instructions/tools.instructions.md` (mention the new orchestration script family)
  - `.github/instructions/integration-testing.instructions.md` (point at the runbook as the canonical entrypoint after the editor is launched)
  - `.github/prompts/godot-runtime-verification.prompt.md` (rewritten per FR-012: numbered copy-paste recipe, "do not source-spelunk" rule, stale-capability stop condition, link to runbook)
  - `.github/agents/godot-evidence-triage.agent.md` (FR-012 hard-stop rule when a fresh run is requested; link to runbook)
  - `addons/agent_runtime_harness/templates/project_root/` (audit only — no agent-facing template files reference the deferred trace work; if any prompt/agent template duplicates the prior runtime-verification prompt, update in lockstep with the `.github/prompts/` rewrite)
  - `specs/008-agent-runbook/quickstart.md` (this feature's own quickstart, Phase 1 output)
- [x] **Addon parse-check planned**: Not applicable — this feature edits zero files under `addons/agent_runtime_harness/`. The Pester suite (`pwsh ./tools/tests/run-tool-tests.ps1`) is the only mandatory check. If, during implementation, any change does touch addon GDScript (it should not), the contributor MUST run `pwsh ./tools/check-addon-parse.ps1` and treat a non-zero exit as blocking.

## Project Structure

### Documentation (this feature)

```text
specs/008-agent-runbook/
├── plan.md               # This file
├── research.md           # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── orchestration-stdout.schema.json
│   ├── runbook-entry.schema.json
│   └── orchestration-cli.md
└── tasks.md              # Phase 2 output (/speckit.tasks - NOT created here)
```

### Source Code (repository root)

```text
RUNBOOK.md                                            # NEW — top-level index

docs/
├── INTEGRATION_TESTING.md                            # MODIFY — add "see also" pointer
└── runbook/                                          # NEW directory
    ├── input-dispatch.md                             # NEW
    ├── inspect-scene-tree.md                         # NEW
    ├── behavior-watch.md                             # NEW
    ├── build-error-triage.md                         # NEW
    └── runtime-error-triage.md                       # NEW

tools/
├── README.md                                         # MODIFY — inventory + runbook link
├── automation/
│   ├── invoke-input-dispatch.ps1                     # NEW
│   ├── invoke-scene-inspection.ps1                   # NEW
│   ├── invoke-behavior-watch.ps1                     # NEW
│   ├── invoke-build-error-triage.ps1                 # NEW
│   └── invoke-runtime-error-triage.ps1               # NEW
└── tests/
    ├── fixtures/runbook/                             # NEW directory (tracked)
    │   ├── input-dispatch/
    │   │   ├── press-enter.json
    │   │   ├── press-arrow-keys.json
    │   │   └── press-action.json
    │   ├── behavior-watch/
    │   │   └── single-property-window.json
    │   └── inspect-scene-tree/
    │       └── startup-capture.json                  # may simply document "no payload"
    └── InvokeRunbookScripts.Tests.ps1                # NEW — Pester coverage for all 5 scripts

.github/
├── copilot-instructions.md                           # MODIFY — validation commands
├── prompts/
│   └── godot-runtime-verification.prompt.md         # MODIFY — point at runbook, anti-spelunk rule
├── agents/
│   └── godot-evidence-triage.agent.md               # MODIFY — hard-stop rule, link to runbook
└── instructions/
    ├── tools.instructions.md                         # MODIFY — mention invoke-*.ps1 family
    └── integration-testing.instructions.md           # MODIFY — runbook as entrypoint

AGENTS.md                                             # MODIFY — validation expectations
```

**Structure Decision**: All paths above already exist as established repository
locations except `RUNBOOK.md` (new top-level), `docs/runbook/` (new),
`tools/tests/fixtures/runbook/` (new). These additions are minimal and
follow existing conventions (top-level `README.md`/`AGENTS.md` precedent
for `RUNBOOK.md`; `docs/<topic>/` precedent for sub-directories;
`tools/tests/fixtures/<feature>/` precedent set by the pong-testbed tree).
No write-boundary changes are required because none of these paths is
listed in `tools/automation/write-boundaries.json` as restricted.

## Complexity Tracking

> No Constitution Check violations to justify. This feature is pure
> repo-side tooling and documentation; it stays strictly above the
> plugin layer and reuses existing helpers verbatim.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| *(none)*  | —          | —                                    |
