---
description: Run Scenegraph Harness runtime verification for a Godot change, combine existing tests when needed, and report the result from manifest-centered evidence.
---

## Mission

Interpret a Godot change request, choose between ordinary tests, Scenegraph Harness runtime verification, or combined validation, and prove any runtime-visible claim from persisted evidence without broad repo rediscovery.

## Inputs

- Change request or verification request
- Project root when runtime verification is needed
- Optional deterministic test command or existing test surface to include in combined validation
- Optional expected runtime node, hierarchy, or gameplay symptom

## Scope

- Read `.github/copilot-instructions.md`, `AGENTS.md`, and any relevant `.github/instructions/*.instructions.md` file before acting.
- Route runtime-visible requests to the Scenegraph Harness workflow.
- If the user already provides an evidence manifest and only wants diagnosis, stop and route to `godot-evidence-triage.agent.md`.
- For runtime verification from this repository checkout, prefer `tools/automation/get-editor-evidence-capability.ps1` and `tools/automation/request-editor-evidence-run.ps1` over hand-editing broker files.
- Read the manifest first once a run has persisted evidence.
- Keep recommendations plugin-first and grounded in structured runtime evidence.

## Stop conditions

- Capability is blocked, missing, or schema-invalid.
- Final run result is blocked or failed before a persisted bundle is available.
- The task requires fabricating a new ordinary test suite only to satisfy combined validation.
- The requested work requires writes outside a declared boundary for any autonomous artifact involved.

## Expected outputs

- The selected validation mode with a short reason
- The runtime verification outcome or explicit blocked reason
- Whether existing ordinary tests were also run or should run
- The next validation or debugging step grounded in the manifest or run result
