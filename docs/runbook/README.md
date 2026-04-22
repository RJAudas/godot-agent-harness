# Runbook Recipes — Index

This directory contains one recipe file per supported harness workflow.

| Recipe | Workflow |
|---|---|
| [input-dispatch.md](input-dispatch.md) | Input dispatch |
| [inspect-scene-tree.md](inspect-scene-tree.md) | Scene inspection |
| [behavior-watch.md](behavior-watch.md) | Behavior watch |
| [build-error-triage.md](build-error-triage.md) | Build-error triage |
| [runtime-error-triage.md](runtime-error-triage.md) | Runtime-error triage |

## Canonical do-not-read-addon-source callout

Every recipe's **Anti-patterns** section MUST include the following marker
block verbatim. Copy-paste it exactly — the Pester static-check scans for
`<!-- runbook:do-not-read-addon-source -->` and `<!-- /runbook:do-not-read-addon-source -->`
as its boundary markers.

```markdown
<!-- runbook:do-not-read-addon-source -->
> **Do not** read files under `addons/agent_runtime_harness/` to understand
> what inputs are valid or what the runtime does. All valid inputs are
> documented in `specs/` and `docs/`. Reading addon source is slow, fragile,
> and likely to mislead.
<!-- /runbook:do-not-read-addon-source -->
```

This rule is enforced by the `Describe 'RUNBOOK static checks'` Pester block
in `tools/tests/InvokeRunbookScripts.Tests.ps1` (SC-002).
