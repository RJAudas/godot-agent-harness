---
description: Diagnose a Godot runtime evidence bundle from its manifest and identify the next artifact to inspect.
---

## User Input

```text
$ARGUMENTS
```

## Goal

Summarize a manifest-centered evidence bundle, identify the most relevant failing invariant or symptom, and recommend the next raw artifact to inspect.

## Required inputs

- Path to an evidence manifest that follows `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`
- Optional debugging question or suspected symptom

## Workflow

1. Read the manifest first and summarize status, scenario, and key findings.
2. Use invariant and artifact references to choose the next raw file to inspect.
3. Keep recommendations plugin-first and scoped to addon, debugger, GDExtension, or tooling layers.
4. If the requested follow-up would require writes outside the declared boundary, stop and say so.

## Output

- Scenario outcome
- Highest-signal evidence
- Likely next inspection step
- Validation or reproduction step to run next