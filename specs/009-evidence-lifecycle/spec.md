# Feature Specification: Run-Artifact Evidence Lifecycle

**Feature Branch**: `009-evidence-lifecycle`
**Created**: 2026-04-23
**Status**: Draft

## Clarifications

### Session 2026-04-23

- Q: Does pinning a completed run move or copy the artifacts? → A: Copy — pinning duplicates the artifacts into the pinned zone; the original transient files remain until the next run's automatic cleanup.
- Q: Disposition of the 13 run-produced files currently tracked under `tools/tests/fixtures/pong-testbed/evidence/automation/`? → A: Remove from the index; extend `.gitignore` so fixture-tree `evidence/**` and `harness/automation/results/**` paths are never tracked going forward.
- Q: Pin-name collision behavior? → A: Refuse with a clear error by default; require an explicit `-Force` (or equivalent) flag to overwrite an existing pin.
- Q: Concurrent runs against the same sandbox? → A: Detect and reject — the orchestration script leaves an in-flight marker in the transient zone; a second concurrent invocation fails fast with a clear error pointing at the active run.
- Q: What files are included when pinning a run? → A: The evidence manifest and all artifacts it references, **plus** the orchestration-level `run-result.json` and `lifecycle-status.json` from `harness/automation/results/` — i.e., everything an agent would read on a live run, so pinned and live runs are directly comparable.

---

**Input**: User description: "We need a way to clean up the testing json files between runs and git. Agents are getting confused when seeing data from previous runs and checking in and creating history on file runs doesn't seem to be a good idea. We need a way to keep this clean and organize it so the agents can run multiple times and maybe reference previous runs on purpose not on accident. Maybe the agents should know how to clean up previous run information when it makes sense?"

## Problem Statement *(context, not requirements)*

The harness writes runtime evidence back into the project it is running against. Today that evidence sits in two mixed-purpose places:

- `harness/automation/results/` inside whatever project the editor/runtime is attached to (produces `capability.json`, `lifecycle-status.json`, `run-result.json`).
- `evidence/automation/<run-id>/` inside the same project (produces `evidence-manifest.json` plus workflow-specific artifacts such as `trace.jsonl`, `scenegraph-snapshot.json`, `input-dispatch-outcomes.jsonl`).

This layout creates three recurring problems that waste agent runs and pollute history:

1. **Stale files masquerade as live evidence.** Between runs, the previous `run-result.json` and `lifecycle-status.json` remain on disk with the same names. An agent that skips the liveness check — or that is running an unrelated workflow in the same sandbox — reads yesterday's answer and acts on it. The CLAUDE.md rule "do not read prior-run artifacts to plan a new run" exists precisely because the file layout makes the mistake easy.
2. **Run output has leaked into git.** Thirteen runtime-produced files are currently tracked under `tools/tests/fixtures/pong-testbed/evidence/automation/…` because the pong fixture doubles as a run target. Every subsequent run against that fixture produces noisy diffs that either get committed (growing history with meaningless deltas) or hand-reverted (burning agent and reviewer time). The `integration-testing/*` zone is correctly ignored, but the fixture zone is not.
3. **No first-class way to keep a prior run on purpose.** An agent investigating a regression often needs to diff "the run that showed the bug" against "the run that proves the fix." Today the only option is to rename directories by hand or copy files out of the project. Because there is no supported mechanism, agents either don't do it (losing the comparison) or do it inconsistently (leaving debris behind).

The harness already has canonical request fixtures, orchestration scripts, and a manifest contract. What it lacks is a declared **lifecycle** for the files those scripts produce: where they live, how long they live, how a new run gets a clean slate, how a prior run gets deliberately preserved, and what git should and should not see.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clean slate before every run (Priority: P1)

An agent invokes an `invoke-*.ps1` script against an integration-testing sandbox. Before the harness writes anything, the orchestration layer clears the transient result files from the prior run so there is no ambiguity about which `run-result.json` or `lifecycle-status.json` reflects the current request. If the script exits before producing a result, the transient zone still ends in a well-defined state (either empty or containing only the in-progress run's files).

**Why this priority**: This is the single highest-leverage fix. Every runtime-verification workflow depends on the agent reading "the" result file and knowing it belongs to the request it just issued. Removing the "stale file" failure mode eliminates a class of incorrect agent conclusions at the root.

**Independent Test**: Run `invoke-input-dispatch.ps1` twice in a row against the same sandbox with different fixtures. Between runs, inspect `harness/automation/results/`. The second run's files must not contain any field values from the first run, and no file older than the second run's start timestamp may remain in the transient zone. The script must produce the same manifest-path envelope output that 008-agent-runbook already contracts.

**Acceptance Scenarios**:

1. **Given** a sandbox with a completed prior run's `run-result.json` and `lifecycle-status.json` on disk, **When** an agent invokes any orchestration script, **Then** those transient files are removed or overwritten atomically before the new request is dispatched, and no field from the prior run is observable in the new output.
2. **Given** an orchestration script fails before the runtime produces results, **When** the agent retries, **Then** the retry behaves identically to the first invocation — no partial prior-run data is reused.
3. **Given** two agents run back-to-back against the same sandbox with different workflows (e.g., scene inspection then input dispatch), **When** the second agent reads its manifest, **Then** the manifest and its referenced artifacts belong exclusively to the second run.

---

### User Story 2 - Run output never reaches git unless declared a fixture (Priority: P1)

A developer or agent runs the harness and produces evidence artifacts inside the repository working tree. `git status` must not surface those artifacts as untracked or modified files. Only files explicitly declared as canonical fixtures (committed, reviewed, used as test oracles) appear in diffs. The 13 accidentally-committed run artifacts currently under the pong-testbed fixture are either reclassified as intentional fixtures or removed.

**Why this priority**: Every accidentally committed run artifact either grows history with meaningless deltas or forces a hand-cleanup burning reviewer attention. This is the root cause of the user's "checking in and creating history on file runs doesn't seem to be a good idea" complaint.

**Independent Test**: Starting from a clean working tree, run each canonical `invoke-*.ps1` script once against every supported testbed (pong, input-dispatch sandbox, runtime-error-loop sandbox). Then run `git status`. The output must show zero modified or untracked files under any runtime-output path. Re-running the same scripts must continue to produce zero diffs.

**Acceptance Scenarios**:

1. **Given** a clean working tree, **When** an agent runs any orchestration script and the run produces manifests, results, and workflow artifacts, **Then** `git status` reports no changes.
2. **Given** the repository as it stands today with 13 run-produced files tracked under `tools/tests/fixtures/pong-testbed/evidence/automation/`, **When** this feature lands, **Then** those files are removed from the index and covered by new ignore rules so re-running the fixture produces no git diff.
3. **Given** a fresh contributor clones the repo and runs the harness for the first time, **When** they check git status after the run, **Then** they do not need to learn ad-hoc exclusion rules to get a clean tree.

---

### User Story 3 - Deliberately preserve a prior run for comparison (Priority: P2)

An agent (or human) investigating a regression captures the run that reproduces the bug, names it, and keeps it alongside future runs without any risk of it being overwritten or clobbered by the next invocation. A later run that fixes the bug can reference the pinned run by name to diff outcomes, without the agent having to copy files around by hand.

**Why this priority**: This is the feature the user explicitly asked for — "maybe reference previous runs on purpose not on accident." It is P2 rather than P1 because the repo currently has no workflow that blocks on it, but it is the affordance that lets the cleanup rules in US1/US2 be aggressive without losing useful history.

**Independent Test**: Run the harness, then invoke a pin operation that labels the just-finished run. Invoke the harness a second time. Confirm the pinned run's files are unchanged (byte-identical) and the second run's transient files are cleaned per US1. An agent workflow that asks "compare current behavior-watch trace to the pinned baseline" must be able to locate both sets of files from documented paths.

**Acceptance Scenarios**:

1. **Given** a just-completed run whose evidence an agent wants to preserve, **When** the agent pins the run, **Then** the run's artifacts move to (or are copied to) a durable location that is immune to the cleanup behavior in US1.
2. **Given** a pinned prior run exists, **When** any subsequent orchestration script runs, **Then** the pinned run's files are not modified, deleted, or overwritten.
3. **Given** an agent is asked to "compare against the baseline run," **When** it consults the runbook, **Then** there is a single documented way to enumerate pinned runs and find their manifest paths.

---

### User Story 4 - Agents know when and how to clean up (Priority: P2)

Agent-facing documentation (AGENTS.md, CLAUDE.md, runbook recipes) tells agents exactly when cleanup is automatic, when it is their responsibility, and what the one supported command is for each case. An agent that wants to start from a known-clean state has one tool call to do so. An agent that wants to preserve a prior run has one tool call to do that instead. Neither case requires the agent to hand-author file-system operations.

**Why this priority**: The user specifically asked whether agents should "know how to clean up previous run information when it makes sense." The answer is yes, but only through documented, named operations — not by inventing `Remove-Item` calls in prompts.

**Independent Test**: Search the agent-facing docs for references to per-file deletion or ad-hoc cleanup logic. The only cleanup instructions present must point to the named operations this feature provides. A dry-run invocation of each cleanup operation must print the exact set of paths it would touch, so an agent can confirm intent before committing to the action.

**Acceptance Scenarios**:

1. **Given** an agent needs a clean state before a new run, **When** it consults the runbook, **Then** it finds one named operation (with script path and parameters) that performs the cleanup and nothing else.
2. **Given** an agent considers whether to clean up, **When** it reads the guidance, **Then** the default is "the orchestration script already handled it — do nothing" and escalation to an explicit cleanup is reserved for clearly described cases (e.g., sandbox reset, pinned-run housekeeping).
3. **Given** an agent runs a cleanup operation in dry-run mode, **When** it reads the stdout, **Then** it sees a structured list of paths that would be affected and no filesystem mutation has occurred.

---

### Edge Cases

- A run is interrupted (agent cancelled, editor crashed) leaving a half-written `run-result.json` on disk. The next run's cleanup must handle this without surfacing the partial file as "the" prior run or treating it as corrupt input.
- Two processes attempt to run the harness against the same sandbox simultaneously. The in-flight marker (FR-013) causes the second invocation to fail fast with an error naming the active run — cleanup and dispatch are never interleaved.
- A prior run's in-flight marker persists after its owning process died (crash, kill, machine reboot). The next orchestration invocation must detect the stale marker and either clear it automatically (based on liveness check) or surface a recovery instruction in the stdout envelope — never leave the sandbox permanently locked.
- A fixture directory that doubles as a run target (pong-testbed today) — the runtime writes into it, but its canonical `*.expected.json` oracle files live in the same tree. Cleanup must distinguish "run output" from "test oracle" so the latter is never touched.
- A pinned run exists, then a developer renames or moves the sandbox directory. Pinned-run references must fail loudly with a clear message rather than silently pointing at nothing.
- An agent attempts to pin a run that did not produce a manifest (e.g., failed before evidence assembly). The pin operation must refuse with a reason rather than pinning an empty set.
- An agent attempts to pin under a name that already exists. The operation must refuse with a clear error identifying the existing pin; an explicit force flag is required to overwrite.
- Disk-space or permission failure during cleanup — the run proceeds with a warning, or halts, per an explicit and documented choice (not silent partial cleanup).
- A fresh clone of the repo: no `harness/automation/results/` directory yet exists. Every orchestration script and cleanup operation must succeed against an empty or missing transient zone.

## References *(mandatory)*

### Internal References

- [CLAUDE.md](../../CLAUDE.md) — "Do not read prior-run artifacts to plan a new run" and the transient-zone layout.
- [AGENTS.md](../../AGENTS.md) — current validation routing and write-boundary guidance.
- [docs/INTEGRATION_TESTING.md](../../docs/INTEGRATION_TESTING.md) — the `integration-testing/*` sandbox convention (already git-ignored).
- [RUNBOOK.md](../../RUNBOOK.md) — workflow-to-script mapping; any new cleanup or pin operations must appear here.
- [specs/008-agent-runbook/contracts/orchestration-stdout.schema.json](../008-agent-runbook/contracts/orchestration-stdout.schema.json) — envelope schema that existing orchestration scripts honor; any cleanup operation should emit a compatible envelope or a clearly distinct one.
- [tools/automation/write-boundaries.json](../../tools/automation/write-boundaries.json) — declared write zones for autonomous artifacts.
- [.gitignore](../../.gitignore) — current ignore rules, including `integration-testing/*`.

### External References

- [Godot Editor — Project file system](https://docs.godotengine.org/en/stable/tutorials/editor/project_manager.html) — file layout expectations for an embedded project.
- [Git — gitignore pattern format](https://git-scm.com/docs/gitignore) — rules for adding per-path ignore entries without overriding higher-priority excludes.

### Source References

- `addons/agent_runtime_harness/editor/` — writers for `harness/automation/results/*.json` and the artifact store.
- `addons/agent_runtime_harness/runtime/` — writers for `evidence/automation/<run-id>/` manifests and traces.
- `tools/automation/invoke-*.ps1` — orchestration scripts whose pre-run cleanup behavior this feature specifies.
- `tools/tests/fixtures/pong-testbed/evidence/automation/` — the 13 currently-tracked run artifacts that motivate User Story 2.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST define two named zones for harness output inside any target project: a **transient zone** (cleared between runs) and a **pinned zone** (never cleared except by explicit agent/user action). Existing paths (`harness/automation/results/`, `evidence/automation/<run-id>/`) MUST be classified into exactly one zone, and the classification MUST be discoverable from a single documented location.
- **FR-002**: Every orchestration script (`tools/automation/invoke-*.ps1`) MUST clear the transient zone of prior-run files before dispatching its request, and MUST do so atomically enough that no agent can observe a mix of prior-run and current-run files through the stdout envelope's `manifestPath` or any referenced artifact.
- **FR-003**: The system MUST ensure `git status` shows no modified or untracked files in either zone after any number of harness runs against a clean tree. This applies equally to `integration-testing/*` sandboxes and to any fixture directory used as a runtime target.
- **FR-004**: The 13 run-produced files currently tracked under `tools/tests/fixtures/pong-testbed/evidence/automation/` MUST be removed from the git index. `.gitignore` MUST be extended so that fixture-tree `evidence/**` and `harness/automation/results/**` paths — in any fixture directory that doubles as a runtime target — are never tracked again. The Pester suite's committed `*.expected.json` oracle files under `tools/tests/fixtures/pong-testbed/harness/automation/results/` are unaffected and remain tracked.
- **FR-005**: The system MUST provide a named, documented operation for **pinning** a completed run: the pinned artifacts are **copied** into the pinned zone under a stable, agent-chosen name, and are thereafter immune to the transient-zone cleanup in FR-002. The pinned copy MUST include the `evidence-manifest.json`, every artifact the manifest references, **and** the orchestration-level `run-result.json` and `lifecycle-status.json` (when present) from `harness/automation/results/`, so that a pinned run is directly comparable to a live run using the same reads an agent would perform normally. The original transient-zone copies remain untouched by the pin operation itself and are removed only by the next run's automatic cleanup (FR-002), so a `manifestPath` already returned to the agent remains valid until the next invocation. If a pin with the chosen name already exists, the operation MUST refuse with a clear error identifying the existing pin; overwriting is allowed only when the caller passes an explicit force flag (e.g., `-Force`).
- **FR-006**: The system MUST provide a named, documented operation for **enumerating** pinned runs (returning at minimum the pin name and the manifest path for each) so an agent can locate prior runs by identifier rather than by searching the filesystem.
- **FR-007**: The system MUST provide a named, documented operation for **removing** a pinned run when the agent/user decides it is no longer useful. This operation MUST support a dry-run mode that emits the exact set of paths it would touch before any filesystem mutation.
- **FR-008**: Agent-facing documentation (CLAUDE.md, AGENTS.md, RUNBOOK.md, the per-workflow recipes under `docs/runbook/`) MUST be updated to describe: which zone each artifact lives in, that transient-zone cleanup is automatic (agents do nothing), and that pin/unpin/list are the only supported cleanup/preservation operations.
- **FR-009**: Cleanup operations MUST NOT touch files outside the declared transient zone. In particular, fixture oracle files (`*.expected.json`, canonical request fixtures, committed reference manifests) MUST remain untouched regardless of the sandbox layout.
- **FR-010**: When the transient zone cannot be fully cleared (permissions, locks, disk errors), the orchestration script MUST halt before dispatching the request and surface a clear failure in the stdout envelope — silent partial cleanup is prohibited.
- **FR-013**: Orchestration scripts MUST serialize runs against the same sandbox by writing an **in-flight marker** into the transient zone immediately before cleanup, clearing it on completion (success or failure). A second orchestration invocation that finds the marker present MUST fail fast with a clear error identifying the active run (request id or timestamp) rather than proceeding with cleanup or dispatch. A stale marker whose owning process no longer exists MUST be recoverable without manual filesystem intervention.
- **FR-011**: This feature operates entirely at the PowerShell orchestration layer and within agent-facing docs; it does not require new Godot editor, autoload, debugger, or GDExtension points. The addon continues to write through its existing artifact-store interfaces.
- **FR-012**: The system MUST emit or identify the machine-readable runtime artifacts agents will inspect to validate behavior. The existing `evidence-manifest.json` and workflow-specific artifacts remain authoritative; pin/list operations additionally emit a structured pinned-run index that agents can parse.

### Key Entities

- **Transient zone**: The per-project directories into which each new harness run writes capability, lifecycle, result, and evidence files. Cleared before every run. Never tracked by git. Also holds the in-flight marker that serializes concurrent orchestration attempts.
- **In-flight marker**: A small file in the transient zone that records the active run's identifier (and enough metadata to detect staleness). Present for the duration of a run; its presence causes a concurrent orchestration invocation to fail fast.
- **Pinned zone**: A per-project directory (or repo-level store, if the feature design chooses that) holding runs that an agent or human has deliberately preserved. Each pinned run is identified by a stable name and contains the full set of artifacts the original manifest referenced. Immune to automatic cleanup; not tracked by git by default.
- **Pinned run**: A snapshot of one completed harness run, captured by copying its artifacts under a named identifier. Contains the `evidence-manifest.json`, every artifact that manifest references, and the orchestration-level `run-result.json` and `lifecycle-status.json` (when present) — the full set of files an agent would normally read for that run. The copy is independent of — and survives — the transient-zone cleanup.
- **Pinned-run index**: The machine-readable listing that the pin-enumeration operation returns, mapping each pin name to its manifest path and (optionally) metadata such as the scenario id, timestamp, and outcome status.
- **Run oracle fixture**: A file that looks like run output (e.g., `run-result.success.expected.json`) but is a committed test oracle used to validate harness behavior. Lives under `tools/tests/fixtures/` and is explicitly **not** in the transient or pinned zones.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After running the full set of canonical orchestration scripts against every supported sandbox starting from a clean working tree, `git status` reports zero modified or untracked files under any harness-output path. This is verifiable by a CI check that runs the scripts and then asserts `git status --porcelain` is empty for the transient and pinned zones.
- **SC-002**: Across two back-to-back invocations of any orchestration script against the same sandbox, an automated test confirms that no field value from the first run's `run-result.json` appears in the second run's `run-result.json`, `lifecycle-status.json`, or referenced manifest artifacts.
- **SC-003**: An agent asked to "preserve the current run and then reproduce the issue on a clean slate" completes both steps using documented named operations only, with zero hand-authored filesystem commands and at most 3 tool calls total.
- **SC-004**: The 13 currently-committed run-produced files under `tools/tests/fixtures/pong-testbed/evidence/automation/` are removed from the index, and subsequent harness runs against that fixture produce zero git diff. This is verifiable by `git ls-files tools/tests/fixtures/pong-testbed/evidence/automation/` returning empty after the change.
- **SC-005**: A fresh contributor running the harness for the first time, following the updated docs, produces a clean `git status` after their first successful run without needing to read cleanup scripts or filesystem conventions beyond the runbook row.
- **SC-006**: Agent-facing recipes reference exactly one cleanup mechanism per case (automatic pre-run clear, pin, unpin, list). A static check over `docs/runbook/` and `AGENTS.md` confirms no recipe instructs an agent to perform ad-hoc deletions or renames on harness output paths.

## Assumptions

- The pong-testbed fixture's 13 currently-tracked evidence files are there by accident, not by deliberate design — confirmed in clarification and captured in FR-004. The real committed test oracles live in sibling `*.expected.json` files under `tools/tests/fixtures/pong-testbed/harness/automation/results/` and are unaffected by this feature.
- The harness continues to assume one agent at a time performs useful work against a given sandbox. Concurrent orchestration attempts are now **actively rejected** via the in-flight marker (FR-013) rather than merely discouraged; a separate spec can lift this to cooperative concurrency if the need arises.
- The pinned zone lives inside the target project's working tree by default (mirroring how the transient zone works), and is git-ignored by default. A future extension could relocate pinned runs outside the project; that is out of scope here.
- The `integration-testing/*` git-ignore rule remains the correct pattern for sandboxes; this feature extends — rather than replaces — that approach for fixture directories that double as run targets.
- Orchestration scripts remain the single entry point for agents. No new MCP server or editor-UI surface is required; cleanup and pin operations are exposed as the same kind of `invoke-*.ps1`-style scripts and stdout envelopes already contracted in 008-agent-runbook.
- Relevant Godot APIs, where touched at all, can be validated against `docs/GODOT_PLUGIN_REFERENCES.md` and the local `../godot` checkout. This feature is not expected to require new Godot API usage; the runtime side already writes the files the lifecycle rules classify.
- The CLAUDE.md constraint "do not read prior-run artifacts to plan a new run" remains in force and is reinforced — not replaced — by this feature. The pin operation is the sanctioned path for the cases where cross-run reference is legitimate.
