---
description: Diagnose a Godot scenegraph evidence bundle from its manifest and identify the next artifact to inspect.
---

## User Input

```text
$ARGUMENTS
```

## Goal

Summarize a manifest-centered scenegraph evidence bundle, identify the most relevant runtime finding, and recommend the next artifact to inspect only if the manifest indicates it is needed.

## Required inputs

- Path to `evidence/scenegraph/latest/evidence-manifest.json` or another generated scenegraph manifest
- Optional debugging question or expected runtime node/path

## Workflow

1. Read the manifest first and summarize run status, scenario, and key findings.
2. Read the summary artifact next.
3. Read diagnostics only if the manifest or summary indicates a partial or failed run.
4. Read the full snapshot only if you need exact node paths, hierarchy details, or property state.
5. Stay in post-run diagnosis mode. If the user needs a fresh runtime proof instead of diagnosis of an existing bundle, hand off to `godot-runtime-verification.prompt.md`.
6. Distinguish gameplay failures from harness wiring failures such as missing autoload setup or no persisted evidence bundle.

## Output

- Scenario outcome
- Highest-signal evidence
- Whether the expected runtime node or hierarchy was found
- Likely next inspection step if more evidence is needed
