# Feature Specification: Agent Runbook & Parameterized Harness Scripts

**Feature Branch**: `008-agent-runbook`  
**Created**: 2026-04-22  
**Status**: Draft  
## Clarifications

### Session 2026-04-22

- Q: Should diagnosis trace instrumentation (per `RUNTIME_VERIFICATION_AGENT_UX.md`) be in scope for this feature? → A: Out of scope — defer to a follow-on spec; note as future work in Assumptions.
- Q: What is the default capability freshness window for orchestration scripts (FR-005)? → A: 5 minutes (300 seconds), matching `RUNTIME_VERIFICATION_AGENT_UX.md` §Phase 2.
- Q: What is the default end-to-end run timeout for orchestration scripts? → A: 60 seconds, configurable via `-TimeoutSeconds`.
- Q: Should orchestration scripts also accept inline JSON request payloads in addition to fixture file paths? → A: Yes — support both `-RequestFixturePath` (primary) and inline JSON, mutually exclusive; runbook recipes use fixture path.
- Q: How is SC-002 ("zero reads of addon GDScript source") verified given trace instrumentation is out of scope? → A: Reword as a verifiable structural target — recipes/prompts forbid pointing agents at addon source, enforced by a static check that no agent-facing recipe text references `addons/agent_runtime_harness/` paths.

---

**Input**: User description: "agent runbook - streamline agents calling the harness. We built tooling to help agents run a game and check the scene graph, get compile/runtime errors and send keys. Problem is the agents don't know how to use these tools and spend a lot of time trying to figure it out... create a runbook which is a series of example starting points with bullet point instructions. And then we also want to start making well documented parameterized PowerShell scripts where the agent doesn't need to figure out how to perform the tasks on the agent, it only needs to figure out which script is purpose-built for that task and what parameters to supply. Reference RUNTIME_VERIFICATION_AGENT_UX.md."

## Problem Statement *(context, not requirements)*

Coding agents calling the Godot harness today routinely stall on routine tasks like
"launch the game and press Enter." A captured 30-call trace
(see `RUNTIME_VERIFICATION_AGENT_UX.md`) showed three dominant failure modes:

1. **Schema-by-spelunking** — agents grep addon GDScript for invented field
   names because no canonical request fixture exists for common workflows
   (input dispatch, behavior watch, scene inspection).
2. **No single orchestration entrypoint** — even with the right fixture, the
   agent must manually compose `get-editor-evidence-capability.ps1` →
   author JSON → `request-editor-evidence-run.ps1` → poll
   `run-result.json` → read manifest → read outcome JSONL, with
   instructions split across `docs/INTEGRATION_TESTING.md`,
   `tools/README.md`, and per-spec `quickstart.md` files.
3. **Stale evidence mistaken for live state** — agents read prior-run
   `capability.json` / `run-result.json` without checking whether the editor
   is actually running right now.

Existing `AGENTS.md` rules and per-agent prompt files are not enough. Agents
need (a) a single, copy-pasteable starting recipe per workflow, and (b)
purpose-built parameterized scripts that collapse multi-step orchestration
into a single tool call with explicit liveness, timeout, and failure
semantics.

This spec covers the **documentation deliverables (runbook + recipes +
fixture templates)** and the **parameterized orchestration scripts** for
all current harness workflows: scene-graph inspection, build-error reporting,
runtime-error reporting, input dispatch, and behavior-watch sampling. An MCP
server is explicitly out of scope; the deliverables here are designed so
that a future MCP server can wrap them without rework.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - "Press Enter in the running game" via one tool call (Priority: P1)

An agent receives a request like *"launch the game and press Enter, confirm
the menu advances."* It opens `RUNBOOK.md`, finds the *Input dispatch* row,
follows the linked recipe, and runs a single parameterized script with a
ready-made fixture. Within a small bounded number of tool calls it has
structured evidence (manifest path + input-dispatch outcomes) in hand.

**Why this priority**: This is the highest-frequency stall today and the
exemplar use case from `RUNTIME_VERIFICATION_AGENT_UX.md`. Fixing it
proves the runbook + script pattern works.

**Independent Test**: Replay the same prompt that produced the captured
30-call stall trace against the new runbook + script. The agent must
reach an evidence read in ≤ 5 tool calls, perform zero reads of addon
GDScript source, and surface a clear "editor not running" message if
capability data is stale rather than acting on it.

**Acceptance Scenarios**:

1. **Given** the editor is running against an integration-testing sandbox
   and the agent is asked to press Enter, **When** the agent follows the
   runbook recipe, **Then** it invokes the input-dispatch orchestration
   script with a ready-made fixture and receives structured success
   output (manifest path + outcomes) without authoring JSON by hand.
2. **Given** the editor is *not* running, **When** the agent invokes the
   orchestration script, **Then** the script exits with a distinct
   non-success status and a single-line message instructing the agent
   (and user) how to launch the editor — without the agent reading
   addon source or prior `run-result.json`.
3. **Given** the agent is asked to send a sequence other than Enter
   (e.g., arrow keys, an `InputMap` action), **When** it consults the
   runbook, **Then** the runbook points at a sibling fixture template
   that requires only key/action substitution, not schema discovery.

---

### User Story 2 - "Inspect the scene graph after launch" via one tool call (Priority: P1)

An agent is asked *"start the game and tell me what nodes are present in
the main scene."* The runbook directs it to a scene-inspection recipe
that calls a single parameterized script which performs the capability
check, requests a startup capture, polls for completion, and returns the
manifest path plus a pointer to the captured `scene-tree.json`.

**Why this priority**: Scene inspection is the second most common runtime
question agents are asked and shares the same orchestration tax as input
dispatch. Bundling it in the first release validates that the pattern
generalises beyond a single workflow.

**Independent Test**: An agent given a fresh integration-testing sandbox
with the editor running can produce the captured scene tree path with one
script call and zero fixture authoring.

**Acceptance Scenarios**:

1. **Given** a running editor, **When** the agent runs the scene-inspection
   script with `-ProjectRoot`, **Then** the script returns the manifest
   path and the resolved `scene-tree.json` path on stdout in a parseable
   form.
2. **Given** the request fails for any reason (build, runtime, timeout),
   **When** the script exits, **Then** it returns a distinct failure
   classification matching the harness `failureKind` taxonomy and prints
   the diagnostic excerpt the agent needs to act on.

---

### User Story 3 - "Did the build / runtime error?" surfaced cleanly (Priority: P2)

When a harness run fails, the agent should learn the failure category
(build vs runtime vs timeout vs editor-not-running) and the relevant
diagnostic excerpt from a single structured response, instead of having
to open `run-result.json`, then the manifest, then `rawBuildOutput`, then
`runtime-error-records.jsonl` separately.

**Why this priority**: Currently every workflow needs custom failure
triage. Solving it once in the orchestration layer means every recipe in
the runbook benefits.

**Independent Test**: Force a deliberate build error in an integration
sandbox and run any of the orchestration scripts. The single stdout
JSON response must include `failureKind: "build"`, the diagnostic
excerpt, and the manifest path — without the agent having to chase
multiple files.

**Acceptance Scenarios**:

1. **Given** a sandbox with a parse error, **When** any orchestration
   script runs, **Then** stdout JSON carries `failureKind = build` plus
   the relevant diagnostic excerpt (file, line, message), and the
   process exits non-zero.
2. **Given** a runtime crash captured by the spec-007 pipeline, **When**
   the orchestration script completes, **Then** stdout JSON exposes
   `failureKind = runtime`, the latest error record summary, and a
   pointer to `runtime-error-records.jsonl`.

---

### User Story 4 - "Watch a value over time" via one tool call (Priority: P3)

An agent asked to confirm a behavior over time (e.g., *"after I press
Down, does `Player.position.y` decrease?"*) finds a behavior-watch recipe
in the runbook with a parameterized script that accepts the watch
expression(s) and sample window, returns the captured samples, and
points at the manifest.

**Why this priority**: Behavior watch is the lowest-volume workflow today
but exhibits the same fixture-discovery problem. Including it in the
first release closes the gap so no current harness capability is
runbook-less.

**Independent Test**: Given an editor session, an agent can request a
5-second sample of a single property using one script invocation and one
fixture template, with no schema research.

**Acceptance Scenarios**:

1. **Given** a running editor and a target node path, **When** the agent
   runs the behavior-watch script with `-WatchPath`, `-WatchExpression`,
   and `-SampleWindowSeconds`, **Then** it receives the manifest path
   and a pointer to the samples artifact.

---

### Edge Cases

- The editor was launched against a different project root than the one
  the agent supplies → script must report that mismatch using the same
  "editor not running here" message rather than silently using stale
  capability data.
- A previous run's `run-result.json` exists but is older than the current
  request → script must distinguish "the run I just requested completed"
  from "I am reading a prior run" using a freshness signal (e.g., a
  request token round-tripped through the result, or a strict timestamp
  comparison).
- The agent supplies an unknown fixture path → script fails fast with a
  message naming the fixtures directory and listing available templates.
- The orchestration script is invoked from outside the repo root → the
  script must accept a repo-relative `-ProjectRoot` and resolve all
  helper script paths relative to its own location, not the caller's CWD.
- A workflow lacks a fixture template at first release → the runbook
  entry must still document the manual fallback path so the agent is
  never left with a blank page.

## References *(mandatory)*

### Internal References

- `RUNTIME_VERIFICATION_AGENT_UX.md` — captured stall trace, phased
  approach (this spec implements Phase 1 + Phase 2 across all workflows),
  success criteria.
- `docs/INTEGRATION_TESTING.md` — current end-to-end loop the runbook
  must collapse into per-workflow recipes.
- `tools/README.md` — current tool inventory and resolution rules
  (e.g., Godot binary discovery) the new scripts must reuse, not
  duplicate.
- `.github/prompts/godot-runtime-verification.prompt.md` and
  `.github/agents/godot-evidence-triage.agent.md` — must be updated to
  point at the new runbook and to add the "do not source-spelunk" /
  stale-capability stop conditions.
- `tools/automation/get-editor-evidence-capability.ps1`,
  `tools/automation/request-editor-evidence-run.ps1`,
  `tools/evidence/validate-evidence-manifest.ps1` — building blocks the
  parameterized scripts wrap; they remain the canonical low-level API.
- `specs/006-input-dispatch/contracts/`, `specs/005-behavior-watch-sampling/`,
  `specs/004-report-build-errors/`, `specs/007-report-runtime-errors/`,
  `specs/002-inspect-scene-tree/` — schema sources of truth that fixture
  templates must conform to.
- `tools/tests/fixtures/pong-testbed/harness/automation/requests/` —
  existing tracked request fixtures the new templates should mirror in
  shape and validation.

### External References

- None required for this feature; all referenced behavior is defined by
  prior repo specs and existing harness contracts.

### Source References

- None required; this feature does not depend on engine internals in
  `../godot`. All behavior is plugin-layer.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST provide a top-level `RUNBOOK.md` that
  serves as the single starting point for an agent looking up "how do I
  do X with the harness?" It MUST list every supported workflow
  (scene-graph inspection, build-error reporting, runtime-error
  reporting, input dispatch, behavior-watch sampling), with for each:
  a one-line description, the canonical orchestration script to call,
  the canonical fixture template (if any), and a link to a per-workflow
  recipe.
- **FR-002**: The repository MUST provide one per-workflow recipe file
  per supported workflow under `docs/runbook/`. Each recipe MUST be a
  numbered, copy-pasteable bullet list that an agent can execute
  top-to-bottom, including: prerequisites, the exact script invocation,
  expected structured output, the failure classes the agent should
  handle, and a "do not do this" section naming the most common
  source-spelunking dead ends.
- **FR-003**: The repository MUST provide ready-to-use, schema-valid
  request fixture templates for every workflow that takes a request
  payload. At minimum: input-dispatch templates for "press Enter,"
  "press arrow keys," and "press an `InputMap` action"; a behavior-watch
  template for a single-expression sample window; and a scene-inspection
  template (or documented startup-capture default if no payload is
  required). Fixtures MUST be tracked under `tools/tests/fixtures/` so
  they live alongside the existing pong-testbed fixtures.
- **FR-004**: The repository MUST provide a parameterized PowerShell
  orchestration script per workflow that wraps capability check →
  request → poll → result-read → outcome-read into a single invocation.
  Each script MUST: (a) accept `-ProjectRoot` and any workflow-specific
  parameters by name, (b) emit machine-readable JSON to stdout for the
  agent, (c) emit a human-readable summary to stderr, (d) exit with a
  distinct non-zero code when the editor is not live against the given
  project root.
- **FR-005**: Orchestration scripts MUST detect a stale or missing
  `capability.json` and refuse to proceed with a clear "launch the
  editor against `<ProjectRoot>`" message. The freshness window MUST be
  configurable via a script parameter and MUST default to **300 seconds
  (5 minutes)**. They MUST NOT fall back to a prior run's data.
- **FR-006**: Orchestration scripts MUST guarantee that the
  `run-result.json` they read corresponds to the run they just
  requested, not a prior run, using a freshness signal explicitly
  documented in the script's comment-based help. Each script MUST
  enforce an end-to-end timeout (capability check + request + poll)
  configurable via a `-TimeoutSeconds` parameter, defaulting to **60
  seconds**. On timeout, the script MUST exit non-zero with
  `failureKind = timeout`.
- **FR-007**: Orchestration scripts MUST classify failures using the
  existing harness `failureKind` taxonomy (e.g., `build`, `runtime`,
  `timeout`, `editor-not-running`, `request-invalid`) and surface, on
  failure, a structured diagnostic excerpt sufficient for the agent to
  act without opening additional files.
- **FR-008**: Each orchestration script MUST include comment-based
  PowerShell help (`<# .SYNOPSIS / .DESCRIPTION / .PARAMETER /
  .EXAMPLE #>`) such that `Get-Help <script>.ps1 -Full` is sufficient
  documentation for an agent to use it without reading the
  implementation.
- **FR-009**: Orchestration scripts and fixture templates MUST be
  designed so that a future MCP server can call them as subprocesses or
  import their parameter contract directly, without re-implementing
  orchestration. This implies: stable parameter names, stable stdout
  JSON schema per script, and no reliance on interactive prompts.
- **FR-009a**: For workflows that take a request payload, orchestration
  scripts MUST accept the payload via either a fixture path (e.g.,
  `-RequestFixturePath`) or an inline JSON string parameter (e.g.,
  `-RequestJson`). The two parameters MUST be mutually exclusive and
  the script MUST fail fast with a clear error when both or neither
  are supplied. Runbook recipes use the fixture path as the primary
  documented happy-path; inline JSON is documented as the one-off /
  programmatic alternative and is the precursor to a future MCP
  `dispatch_keys`-style verb.
- **FR-010**: All orchestration scripts MUST resolve helper script
  paths and the Godot binary using the same conventions already in use
  by `tools/check-addon-parse.ps1` (`$env:GODOT_BIN` → `godot` /
  `godot4` / `Godot*` on `PATH`, then User-scope environment) and MUST
  reuse existing helpers under `tools/automation/` and `tools/evidence/`
  rather than duplicating logic.
- **FR-011**: The runbook MUST include an explicit "do not source-spelunk"
  rule: if a request field name is unknown, the agent consults the
  matching `specs/<id>/contracts/` directory and the fixture templates,
  and does NOT grep addon GDScript for guessed field names.
- **FR-012**: `.github/prompts/godot-runtime-verification.prompt.md` and
  `.github/agents/godot-evidence-triage.agent.md` MUST be updated to
  reference the new runbook as the canonical entrypoint, including the
  triage agent's hard-stop rule when a fresh run is requested.
- **FR-013**: Fixture templates MUST be validated by the existing
  PowerShell test suite (`pwsh ./tools/tests/run-tool-tests.ps1`) so a
  schema regression in any spec breaks the runbook templates loudly.
- **FR-014**: Each orchestration script MUST be covered by at least one
  Pester test that verifies its parameter contract and its
  editor-not-running failure path without requiring a live editor.
- **FR-015**: The feature relies on the addon, autoload, and editor
  debugger layers already provided by prior specs (002, 004, 005, 006,
  007) plus the existing `tools/automation/` and `tools/evidence/`
  PowerShell helpers. It MUST NOT introduce engine-fork changes and MUST
  NOT add new addon code; all new code is repo-side tooling and
  documentation.
- **FR-016**: The machine-readable artifacts agents inspect via the
  runbook are the existing evidence bundle outputs (manifest, scene
  tree JSON, input-dispatch outcomes JSONL, behavior-watch samples,
  build-diagnostic and runtime-error records). The orchestration scripts
  MUST surface the file paths to these artifacts in stdout JSON so
  agents can read them directly.

### Key Entities

- **Runbook (`RUNBOOK.md`)**: Top-level index mapping workflows to
  recipes, scripts, and fixture templates. One row per workflow.
- **Workflow Recipe (`docs/runbook/<workflow>.md`)**: Numbered
  copy-paste recipe for a single workflow including prerequisites,
  invocation, expected output, failure handling, and anti-patterns.
- **Request Fixture Template (`tools/tests/fixtures/<workflow>/*.json`)**:
  Schema-valid, ready-to-pass automation request payloads tracked under
  `tools/tests/fixtures/`, mirroring the pong-testbed pattern.
- **Orchestration Script (`tools/automation/invoke-*.ps1` or analogous)**:
  Parameterized wrapper that performs the full capability → request →
  poll → result loop for one workflow and emits structured stdout JSON.
- **Stdout JSON Contract**: A small, stable per-script JSON shape
  including at minimum `status`, `failureKind` (when applicable),
  `manifestPath` (when produced), and workflow-specific outcome
  pointers. Documented in each script's comment-based help.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For each of the five workflows in scope, an agent
  starting from `RUNBOOK.md` and a running editor reaches a successful
  evidence read in **≤ 5 tool calls** end-to-end.
- **SC-002**: Every workflow recipe in `RUNBOOK.md` and `docs/runbook/`,
  and every updated agent prompt referenced by FR-012, instructs the
  agent to consult fixture templates and `specs/<id>/contracts/` when a
  request field is unknown and explicitly forbids reading addon source
  to derive request shapes. Verified by a static check in the test
  suite that no agent-facing recipe text under `docs/runbook/` or in
  the updated prompt files contains paths under
  `addons/agent_runtime_harness/` outside of an explicit "do not read
  these" callout.
- **SC-003**: When the editor is not running against the supplied
  project root, the agent receives a single clear "editor not running"
  message and stops, with **zero false-positive successful reads of
  stale `run-result.json` data**.
- **SC-004**: When a build, runtime, or timeout failure occurs, the
  agent obtains a correctly classified `failureKind` and an actionable
  diagnostic excerpt from a single script invocation, **without opening
  additional files**, in 100% of failure-path scenarios covered by
  Pester tests.
- **SC-005**: Every workflow listed in `RUNBOOK.md` has, on the same
  page, a working script invocation and a working fixture template
  reference (or documented "no payload needed" note). Verified by a
  link/path-existence check in the test suite.
- **SC-006**: `Get-Help <script>.ps1 -Full` for every orchestration
  script produces complete `.SYNOPSIS`, `.DESCRIPTION`, all
  `.PARAMETER` entries, and at least one `.EXAMPLE` — verified by the
  Pester test suite.

## Assumptions

- Agents have shell access to `pwsh` and to the repo working tree; the
  runbook does not need to teach shell basics.
- The five in-scope workflows already have a working low-level harness
  pipeline shipped by prior specs (002, 004, 005, 006, 007); this
  feature adds documentation and orchestration on top, not new runtime
  capability.
- Integration-testing sandboxes follow the conventions in
  `docs/INTEGRATION_TESTING.md` and live under the git-ignored
  `integration-testing/<name>/` tree.
- A future MCP server, if built, will wrap the orchestration scripts
  rather than re-implement orchestration. This spec deliberately keeps
  MCP design out of scope but constrains the script contracts to be
  MCP-friendly (FR-009).
- The freshness window for `capability.json` (e.g., 5 minutes) is a
  reasonable default for an interactive editor session and is exposed
  as a script parameter so users can tune it without code changes.
- Existing schema sources of truth in `specs/<id>/contracts/` are
  authoritative; fixture templates derive from them, not the reverse.
- Diagnosis trace instrumentation (per `RUNTIME_VERIFICATION_AGENT_UX.md`'s
  "Diagnosis instrumentation" section — appending agent tool-call traces
  to `tools/evals/.../runtime-verification-trace-<ts>.jsonl`) is
  explicitly **out of scope** for this feature and is deferred to a
  follow-on spec. Orchestration scripts here therefore have no
  trace-emission requirement and the runtime-verification agent prompt
  is not extended with self-logging duties in this release.
