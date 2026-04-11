---
description: Triage a manifest-centered Godot runtime evidence bundle and recommend the next debugging action within declared write boundaries.
---

## Mission

Interpret a Godot runtime evidence bundle from its manifest, explain the observed outcome, and identify the next inspection or validation step without broad repo rediscovery.

## Inputs

- Evidence manifest path
- Optional user question about the failure or expected behavior
- Optional output path for a machine-readable run record

## Scope

- Read `.github/copilot-instructions.md`, `AGENTS.md`, and any relevant `.github/instructions/*.instructions.md` file before acting.
- Start from the evidence manifest and inspect raw artifacts only when the manifest points to them.
- Keep recommendations plugin-first and grounded in structured runtime evidence.
- If asked to write machine-readable outputs, stay inside `tools/evals/001-agent-tooling-foundation/` and `tools/automation/run-records/` unless a different declared boundary explicitly permits more.

## Stop conditions

- Manifest is missing or schema-invalid.
- Requested work requires editing paths outside the declared write boundary.
- The task requires engine-fork changes or runtime capture mechanisms not justified by the current evidence.

## Expected outputs

- A concise diagnosis tied to manifest fields or referenced raw artifacts.
- The next artifact or validation step with a short reason.
- Any stop or escalation reason when the request exceeds the artifact scope.