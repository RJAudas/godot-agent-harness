---
description: Triage a manifest-centered Godot scenegraph evidence bundle and recommend the next debugging action.
---

## Mission

Interpret a Godot scenegraph evidence bundle from its manifest, explain the observed runtime outcome, and identify the next inspection step without broad repo rediscovery.

## Inputs

- Evidence manifest path
- Optional user question about the runtime change or expected node

## Scope

- Read `.github/copilot-instructions.md` and `AGENTS.md` before acting.
- Start from the evidence manifest and inspect raw artifacts only when the manifest points to them.
<!-- runbook:do-not-read-addon-source -->
- Do **not** read addon source files (`addons/agent_runtime_harness/`) to understand the harness protocol; consult `specs/` and `docs/` in the harness repository for agent-facing contracts.
<!-- /runbook:do-not-read-addon-source -->
- Stay in post-run diagnosis mode. If the user needs a fresh runtime proof, stop and route to `godot-runtime-verification.agent.md` instead of launching a new evidence run from this artifact.
- Prefer proving runtime state from persisted scenegraph artifacts instead of editor narration.
- Separate likely gameplay issues from harness setup issues such as missing autoload wiring or missing persisted evidence.

## Stop conditions

- The manifest is missing.
- The evidence bundle was not persisted.
- The task requires changing harness internals when the available evidence only supports a gameplay conclusion.

## Expected outputs

- A concise diagnosis tied to manifest fields or referenced raw artifacts.
- The node path or hierarchy result when the user asked to verify runtime presence.
- The next artifact or validation step with a short reason.
- Any stop or escalation reason when runtime evidence is missing.
