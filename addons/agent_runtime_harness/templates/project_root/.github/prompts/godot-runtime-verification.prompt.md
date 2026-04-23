---
description: Drive a Godot runtime verification with the Scenegraph Harness by writing one run-request and reading its evidence. Stay on the fast path.
---

## User Input

```text
$ARGUMENTS
```

## Fast path (for every run-game + optional input request)

If the user says anything like "run the game", "press Enter past the menu", "test the level", or "verify at runtime", do exactly these four steps. **Do not read any other files first.**

1. Check `harness/automation/results/capability.json` exists and its mtime is within the last 5 minutes. If not, stop and report `editor-not-running` — tell the user to launch the editor against the project.
2. Write **one** file at `harness/automation/requests/run-request.json` using the template below. Fill in the `<CHANGE>` fields, leave everything else verbatim.
3. Poll `harness/automation/results/run-result.json` for up to 60 seconds, waiting for a file whose `requestId` equals the one you wrote **and** whose `completedAt` is set.
4. Read the `manifestPath` from that run-result, then the manifest, then the summary artifact referenced by the manifest. That is your evidence.

### Run-request template

Copy verbatim and edit only the `<CHANGE>` fields:

```json
{
  "requestId": "<CHANGE: e.g. agent-YYYYMMDDThhmmssZ-xxxxxx, unique per run>",
  "scenarioId": "agent-runtime-verification",
  "runId": "<CHANGE: same string as requestId is fine>",
  "targetScene": "<CHANGE: e.g. res://scenes/main.tscn>",
  "outputDirectory": "res://evidence/automation/agent",
  "artifactRoot": "evidence/automation/agent",
  "expectationFiles": [],
  "capturePolicy": { "startup": true, "manual": true, "failure": true },
  "stopPolicy": { "stopAfterValidation": true },
  "requestedBy": "agent",
  "createdAt": "<CHANGE: current UTC ISO-8601, e.g. 2026-04-23T15:30:00Z>",
  "inputDispatchScript": {
    "events": [
      { "kind": "key", "identifier": "ENTER", "phase": "press",   "frame": 30 },
      { "kind": "key", "identifier": "ENTER", "phase": "release", "frame": 32 }
    ]
  }
}
```

- For runs with no input, **drop the `inputDispatchScript` field entirely**.
- Key identifiers are bare Godot logical names: `ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`, etc. — **not** `KEY_ENTER`.
- For InputMap actions use `{ "kind": "action", "identifier": "ui_accept", "phase": "press", "frame": 30 }` (plus a matching release).
- `capturePolicy` and `stopPolicy` values above are correct for the overwhelming majority of runs. Do not vary them speculatively.

## Do not

These are the behaviors that waste runs. The agent before you had all of them; yours should have none.

- **Do not read prior-run artifacts to plan a new run.** That includes `run-result.json` from any previous request, `lifecycle-status.json`, earlier `run-request*.json` files, or anything under `evidence/` that was not produced by *your* request. Those files describe the past; they do not tell you what to do now.
- **Do not read addon source files** (`addons/agent_runtime_harness/`) to understand the protocol. Everything you need is in this prompt.
- **Do not spelunk for `stopPolicy`, `capturePolicy`, or event-timing examples** — the template values are correct. Adjust them only after a completed run tells you something specific is wrong.
- **Do not write multiple files, shell out to generate request IDs, or search the repo for sample payloads.** Write one `run-request.json` with the template above.
- **Do not invent an alternate broker entrypoint** (no new scripts, no new directories). One file in, one file out.

## After your run completes

- On success, read `manifestPath` from the fresh `run-result.json`. Read the manifest next, then whichever summary artifact is relevant (e.g. `input-dispatch-outcomes.jsonl` for keypress runs, `scenegraph-summary.json` for state queries).
- If `run-result.json` reports `failureKind = build`, stop before manifest lookup. Report `buildFailurePhase`, each `buildDiagnostics` entry with `resourcePath`, `message`, `line`, and `column`, plus the relevant `rawBuildOutput` lines verbatim.
- If `failureKind = runtime`, read the manifest and `runtime-error-records.jsonl` to report the first failure.
- If the request times out with no matching `run-result.json`, report `timeout` and note that the editor may not be in play mode — the broker only processes requests while the game is running.

## Routing away from this prompt

- If the user already has an `evidence-manifest.json` and only wants diagnosis, hand off to `godot-evidence-triage.prompt.md` instead of starting a new run.
- If the task is a pure unit/contract/schema test with no runtime behavior in scope, use ordinary tests instead.

## Output

- `status`: `success` or `failure`
- `failureKind` on failure (`editor-not-running`, `timeout`, `build`, `runtime`, `request-invalid`)
- `manifestPath` on success
- One-line summary of what happened at runtime (nodes captured, input events dispatched, scene transition observed, etc.)
