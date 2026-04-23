# Phase 0: Research — Agent Runbook & Parameterized Harness Scripts

All Technical Context items resolved. The five clarifications recorded in
`spec.md` already pinned the previously open decisions; this document
captures the remaining design-time choices and the alternatives
considered, so reviewers can audit the trade-offs without re-deriving
them.

## Decision: Stable stdout JSON envelope with workflow-specific `outcome` block

- **Decision**: Every orchestration script writes a single JSON object to
  stdout with the keys `status` (`success` | `failure`),
  `failureKind` (one of `editor-not-running`, `request-invalid`,
  `build`, `runtime`, `timeout`, `internal`; `null` on success),
  `manifestPath` (absolute path to the persisted evidence manifest, or
  `null` if no manifest was produced), `runId`, `requestId`,
  `completedAt` (ISO-8601, UTC), `diagnostics` (an array of one-line
  strings; populated on failure), and `outcome` (workflow-specific
  object documented per script). Human-readable summary goes to stderr.
- **Rationale**: One stable envelope across all five scripts means an
  agent (or future MCP wrapper) learns the contract once. The
  workflow-specific `outcome` block keeps per-workflow data (e.g., the
  list of dispatched events; the `scene-tree.json` path; the samples
  artifact path; the latest runtime error summary) without exploding
  the top-level shape. The envelope is small enough to be JSON-line
  compatible if a caller wants to log it.
- **Alternatives considered**:
  - *Per-script bespoke shapes* — rejected: forces the agent (and the
    future MCP server's tool definitions) to learn five different
    shapes for what is essentially the same orchestration outcome.
  - *Embed full manifest content in stdout* — rejected: bloats the
    envelope, duplicates data already on disk, and tempts agents to
    skip the manifest validator.
  - *Multiple lines of NDJSON* — rejected: harder for a one-shot
    consumer to parse; we never need streaming here because the script
    blocks until completion or timeout.

## Decision: Mutually-exclusive `-RequestFixturePath` and `-RequestJson`

- **Decision**: Each orchestration script that takes a request payload
  exposes both `-RequestFixturePath <path>` and `-RequestJson <json>`,
  enforced as mutually exclusive (PowerShell parameter sets). When
  neither or both are supplied, the script exits with
  `failureKind = request-invalid` and a `diagnostics` entry naming the
  fixtures directory and listing available templates.
- **Rationale**: Pinned by spec clarification Q4. The fixture path is
  the documented happy path in the runbook; inline JSON is the
  precursor to a future MCP `dispatch_keys`-style verb (`runtime.dispatch_keys`
  in the Phase-3 sketch) that builds the payload programmatically.
- **Alternatives considered**: Fixture-only (rejected — forces filesystem
  write for one-off requests); inline-only (rejected — loses the
  "copy this exact fixture" affordance that makes the runbook
  self-documenting).

## Decision: Capability-freshness gate via filesystem mtime, default 300 s

- **Decision**: Each orchestration script first invokes
  `tools/automation/get-editor-evidence-capability.ps1` to refresh
  `harness/automation/results/capability.json`, then asserts the
  resulting file's `LastWriteTimeUtc` is within
  `-MaxCapabilityAgeSeconds` (default 300, configurable). If the file
  is missing or older, the script exits with
  `failureKind = editor-not-running` and a `diagnostics` line of the
  form `"Editor not running against <ProjectRoot>. Launch with: godot --editor --path <ProjectRoot>"`.
- **Rationale**: Pinned by spec clarification Q2.
  `get-editor-evidence-capability.ps1` already writes the capability
  file every call when the editor is live, so checking its mtime is a
  reliable liveness proxy without extending the addon protocol. 300 s
  matches the value already proposed in `RUNTIME_VERIFICATION_AGENT_UX.md`.
- **Alternatives considered**: Heartbeat ping into the addon (rejected —
  would require addon changes, violating the no-addon-edits constraint
  of this feature); reading editor process list (rejected — not
  cross-platform without extra deps).

## Decision: Run-result freshness via per-invocation request token

- **Decision**: Each orchestration script generates a fresh
  `requestId` (`runbook-<workflow>-<UTC-ts>-<short-rand>`) before
  calling `request-editor-evidence-run.ps1`. It then polls
  `harness/automation/results/run-result.json` until the file's
  `requestId` field matches the generated value AND its `completedAt`
  is non-empty, OR the wall-clock budget exceeds `-TimeoutSeconds`
  (default 60). Polling interval defaults to 250 ms; configurable via
  `-PollIntervalMilliseconds`.
- **Rationale**: The existing `run-result.json` is overwritten by the
  next run, so a token round-trip is the simplest unambiguous freshness
  signal. Pinned by spec FR-006 and clarification Q3 (timeout 60 s).
- **Alternatives considered**: Inode-style file rename per run
  (rejected — would require addon changes to write a new filename);
  trusting `completedAt > scriptStart` (rejected — clock skew between
  shell and editor process makes this brittle on Windows).

## Decision: Failure classification taxonomy reuses harness `failureKind`

- **Decision**: The orchestration scripts pass through the
  `failureKind` value from `run-result.json` whenever the editor
  produced one (`build`, `runtime`, `request-invalid`,
  workflow-specific values), and synthesize their own
  (`editor-not-running`, `timeout`, `internal`) when the failure is
  detected before the editor produces a result.
- **Rationale**: Pinned by FR-007. Reuses an established taxonomy that
  agents and the existing test suite already recognize.
- **Alternatives considered**: A new orchestration-only taxonomy
  (rejected — would force agents to learn two parallel error languages).

## Decision: Pester coverage with mocked helper invocations

- **Decision**: New file `tools/tests/InvokeRunbookScripts.Tests.ps1`
  covers each orchestration script with a matrix of: parameter contract
  (mutually exclusive `-RequestFixturePath`/`-RequestJson`; required
  `-ProjectRoot`), capability-stale failure path
  (`failureKind = editor-not-running`), build-failure passthrough
  (`failureKind = build`), runtime-failure passthrough
  (`failureKind = runtime`), timeout (`failureKind = timeout`), and
  success envelope shape. Helper scripts
  (`get-editor-evidence-capability.ps1`,
  `request-editor-evidence-run.ps1`) are invoked via a thin
  `Invoke-Helper` indirection in each script so Pester's `Mock` can
  substitute them without launching an editor.
- **Rationale**: FR-014 requires a Pester test per script; the helper
  indirection is the smallest change that makes the scripts testable
  without spinning up Godot.
- **Alternatives considered**: Real-editor integration tests in CI
  (rejected — out of scope for this feature; live-editor coverage
  remains the responsibility of the integration-testing sandbox flow,
  not CI).

## Decision: SC-002 enforced by static recipe-text check

- **Decision**: Pinned by spec clarification Q5. The Pester suite adds a
  static-text check that scans every `docs/runbook/*.md` file and the
  updated `.github/prompts/godot-runtime-verification.prompt.md` and
  `.github/agents/godot-evidence-triage.agent.md` files for the
  substring `addons/agent_runtime_harness/`. Matches are allowed only
  inside an explicit fenced "do not read" callout (detected by a
  single canonical marker line). Any other match fails the test.
- **Rationale**: Provides a deterministic gate against accidentally
  pointing agents back at addon source — without requiring the deferred
  trace-instrumentation work.
- **Alternatives considered**: Human review only (rejected — not
  enforceable, regresses silently); banning the substring entirely
  (rejected — the "do not read these" callout is itself useful).

## Decision: Trace instrumentation explicitly out of scope

- **Decision**: Pinned by spec clarification Q1. This feature ships no
  agent-side tool-call trace logging; orchestration scripts have no
  trace-emission requirement. A note in the spec's Assumptions section
  records this explicitly so a future spec can pick it up.
- **Rationale**: Bundling trace instrumentation would expand scope and
  add an agent-side recording requirement the orchestration scripts
  themselves don't need to deliver value.
- **Alternatives considered**: Per-invocation log line emitted by the
  scripts (deferred — easy to add later because each script already
  emits a structured stdout JSON object that can double as a log
  record).

## All NEEDS CLARIFICATION resolved

- Trace instrumentation in scope? → out of scope (Q1).
- Capability freshness window default? → 300 s (Q2).
- End-to-end timeout default? → 60 s (Q3).
- Inline JSON request payloads? → yes, mutually exclusive with fixture path (Q4).
- SC-002 verification mechanism? → static recipe-text check (Q5).
