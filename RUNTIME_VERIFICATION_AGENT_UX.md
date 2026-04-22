# Runtime-verification agent UX

> **Phase 1 (fixture templates + runbook) and Phase 2 (parameterized orchestration scripts)
> are now implemented.** Deliverables: `RUNBOOK.md` (five-row quick-reference index),
> `docs/runbook/` (per-workflow recipes), and `tools/automation/invoke-*.ps1`
> (end-to-end orchestration scripts). See `RUNBOOK.md` to run any workflow with a
> single `pwsh` call.

Findings and proposed approach for streamlining "launch the game and send a
keypress" workflows that currently stall the LLM. Start small (fixture
templates + runbook), evolve toward an MCP server only if needed.

## Problem

A simple "launch the game and press Enter" request stalls the LLM. A
captured 30-call trace using the `godot-evidence-triage` agent showed:

1. **Agent-switch is advisory only.** The first message said *"I need to
   route to godot-runtime-verification"* — and then continued in
   `godot-evidence-triage` because VS Code chat agents cannot self-switch.
   Triage-mode never *runs* anything, only reads existing evidence. So the
   LLM was already in the wrong mode from message one.
2. **Schema-by-spelunking.** The agent did not know what fields go in an
   `inputDispatchScript`, so it grepped addon source for invented field
   names (`stopPolicy`, `holdOpen`, `captureDelay`, `postDispatchDelay`,
   `captureAfterDispatch` — none exist). That accounted for ~20 of the 30
   calls. There is no canonical fixture template for "press Enter," so the
   agent re-derived the schema from `quickstart.md` prose plus GDScript.
3. **Stale evidence mistaken for live state.** It read `capability.json`,
   `evidence-manifest.json`, and `run-result.json` from a previous run
   without checking timestamps or confirming the editor was currently
   running. No "is the editor live right now?" gate exists.
4. **No single orchestration entrypoint.** Even with a fixture in hand,
   the agent must compose `get-editor-evidence-capability.ps1` → author
   JSON → `request-editor-evidence-run.ps1` → poll `run-result.json` →
   read manifest → read `input-dispatch-outcomes.jsonl` from prose
   spread across `docs/INTEGRATION_TESTING.md`,
   [tools/README.md](tools/README.md), and
   [specs/006-input-dispatch/quickstart.md](specs/006-input-dispatch/quickstart.md).

The agent in the captured trace never reached fixture authoring.

## Implementation status

**Phase 1 and Phase 2 are complete (spec 008).** The deliverables shipped as:

- Fixture templates under `tools/tests/fixtures/runbook/` (input-dispatch, inspect-scene-tree, build-error-triage, runtime-error-triage, behavior-watch).
- `RUNBOOK.md` — five-row quick-reference index.
- `docs/runbook/` — per-workflow recipe docs with concrete copy-paste commands.
- Five parameterized orchestration scripts under `tools/automation/`: `invoke-input-dispatch.ps1`, `invoke-scene-inspection.ps1`, `invoke-build-error-triage.ps1`, `invoke-runtime-error-triage.ps1`, `invoke-behavior-watch.ps1`.
- Shared module: `tools/automation/RunbookOrchestration.psm1`.
- Pester tests: `tools/tests/InvokeRunbookScripts.Tests.ps1`.

The "Phase 2 orchestration script" described below as a single `invoke-runtime-verification.ps1` was split into five workflow-specific scripts (one per row in RUNBOOK.md) to give agents a narrower, more predictable surface per workflow.

Phase 3 (MCP server) is still optional and has not started.



Three phases. Each phase reuses what the previous one built. Phase 3 (MCP)
is optional; phases 1 and 2 may be sufficient.

### Phase 1 — fixture templates + runbook (cheap)

**Deliverables**

- `tools/tests/fixtures/input-dispatch/press-enter.json`
- `tools/tests/fixtures/input-dispatch/press-arrow-keys.json`
- `tools/tests/fixtures/input-dispatch/press-action.json` (uses an
  `InputMap` action instead of a raw key)

  Each fixture is a complete, schema-valid automation request that can be
  passed straight to `request-editor-evidence-run.ps1 -RequestFixturePath …`
  with no editing.

- Rewrite the **"Runtime verification workflow"** section of
  [.github/prompts/godot-runtime-verification.prompt.md](.github/prompts/godot-runtime-verification.prompt.md)
  as a numbered copy-paste recipe with concrete commands, and add an
  explicit stop condition: *"If `capability.json` is missing or older than
  5 minutes, the editor is not running — stop and ask the user to launch
  it. Do NOT read source code to figure out what to do."*

- Add a **"Do not source-spelunk"** rule: if a request field name is
  unknown, consult `specs/006-input-dispatch/contracts/` and the fixture
  templates. Do not grep the addon for guessed field names.

**Why first**: zero new code, fixes the two highest-frequency stall modes
(schema-by-spelunking and missing runbook).

### Phase 2 — single orchestration script

**Deliverable**: `tools/automation/invoke-runtime-verification.ps1`

Wraps the full loop end-to-end:

```pwsh
pwsh ./tools/automation/invoke-runtime-verification.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/input-dispatch/press-enter.json `
    -TimeoutSeconds 60
```

Behavior:

1. Calls `get-editor-evidence-capability.ps1`. If `capability.json` is
   missing OR its `mtime` is older than `-MaxCapabilityAgeSeconds`
   (default 300), exits with code 2 and a message:
   *"Editor not running against `<ProjectRoot>`. Launch it with
   `godot --editor --path <ProjectRoot>` and re-run."*
2. Calls `request-editor-evidence-run.ps1` with the fixture.
3. Polls `harness/automation/results/run-result.json` for an updated
   `runId`/`completedAt` until timeout.
4. On `failureKind = build`: prints diagnostics and `rawBuildOutput`
   verbatim and exits non-zero.
5. On success: prints the manifest path and the contents of
   `input-dispatch-outcomes.jsonl` (when present).

Output is structured JSON to stdout for the agent to parse, plus a human
summary to stderr.

**Why second**: collapses 4–5 brittle agent steps into one tool call with
explicit liveness, timeout, and failure semantics. The agent's job
becomes "pick a fixture, call one script, read structured output."

### Phase 3 — MCP server (optional)

Only worth doing once 3+ runtime workflows share the same orchestration
tax (input dispatch, behavior watch sampling, build-error reporting,
evidence triage). Until then, phases 1+2 give the same "one tool, one
outcome" feel without an MCP transport.

When the time comes, the MCP server's tools mirror the Phase 2 script's
verbs:

- `runtime.get_capability(project_root)`
- `runtime.invoke_verification(project_root, fixture | script)`
- `runtime.read_manifest(manifest_path)`
- `runtime.read_input_outcomes(run_id)`
- `runtime.dispatch_keys(project_root, keys, action_map?)` — sugar over
  `invoke_verification` that builds the `inputDispatchScript` inline so
  the agent doesn't need a fixture file at all.

**Reuse from phases 1–2**: the MCP tools shell out to (or import the
logic of) the Phase 2 script. The fixture templates from Phase 1 become
the test inputs for the MCP server's regression suite. The diagnosis
trace format from below feeds the MCP server's eval harness.

## Diagnosis instrumentation (do alongside Phase 1)

Have the runtime-verification agent append each tool call and outcome to
`tools/evals/001-agent-tooling-foundation/runtime-verification-trace-<ts>.jsonl`.
After 1–2 stalled sessions, the trace shows exactly which step loops
(today: schema discovery). Use the data to prioritize Phase 2 fixtures
and Phase 3 MCP verbs.

## Routing fix

VS Code chat agents cannot self-switch. Two mitigations:

1. Add to [.github/agents/godot-evidence-triage.agent.md](.github/agents/godot-evidence-triage.agent.md)
   a hard stop: *"If the user asks for a fresh run (launch, press,
   dispatch, reproduce), STOP and tell the user to switch to
   `@godot-runtime-verification`. Do not attempt to run anything."*
2. Once Phase 2 ships, both agents can call
   `invoke-runtime-verification.ps1` — the routing distinction matters
   less because the heavy lifting is in the script.

## Recommended order

1. Phase 1 fixtures + prompt rewrite + stale-capability stop condition.
2. Trace instrumentation; capture one stalled session post-Phase-1 to
   confirm the new failure mode.
3. Phase 2 orchestration script.
4. Re-evaluate MCP after the next 1–2 specs land.

## Success criteria

For "launch the game and press Enter":

- ≤ 5 agent tool calls from request to evidence read.
- Zero reads of addon GDScript source.
- Stale-capability false-positives = 0.
- Wrong-agent silent continuation = 0.

## Open questions

- Trace folder location: `tools/evals/001-agent-tooling-foundation/` (reuse
  existing eval folder) versus a dedicated
  `tools/evals/runtime-verification-traces/`. Decide before Phase 1 so
  the prompt rewrite references the right path.
- Whether the Phase 2 script should also accept an inline
  `-InputDispatchScript` JSON string (skipping the fixture file) — this
  is the natural precursor to the Phase 3 `runtime.dispatch_keys` verb.
