---
applyTo: "tools/**"
---

# Tools Instructions

- Keep scripts deterministic and repo-local. Accept repository-relative paths unless an absolute path is required.
- Emit machine-readable JSON for validation and result files whenever another tool or agent will consume the output.
- `tools/automation/invoke-*.ps1` scripts are the preferred entrypoints for runtime workflows (input dispatch, scene inspection, build-error triage, runtime-error triage, behavior watch) and evidence-lifecycle operations (pin, unpin, list). Runtime-verification scripts emit envelopes conforming to `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`; lifecycle scripts emit `specs/009-evidence-lifecycle/contracts/lifecycle-envelope.schema.json`. Do not parse any output other than these JSON envelopes.
- Evidence lifecycle: the transient zone is cleared automatically before every runtime run. Use `invoke-pin-run.ps1` to preserve a run, `invoke-unpin-run.ps1` to release it, and `invoke-list-pinned-runs.ps1` to enumerate pins. Do not manually delete or copy files under `harness/automation/results/` or `evidence/automation/`.
- Reuse repository schemas from `tools/evals/`, `tools/automation/`, and `specs/001-agent-tooling-foundation/contracts/` instead of inventing one-off JSON shapes.
- Place eval prompts and result files in `tools/evals/`, evidence helpers in `tools/evidence/`, and automation contracts or logs in `tools/automation/`.
- Do not hide side effects. Scripts that write files should make the output path explicit.
- `tools/automation/submit-pause-decision.ps1` writes a validated `pause-decision.json` into `harness/automation/requests/` inside a live integration-testing project root. Keep it aligned with `specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json`.
- New artifact kinds from specs/007 are `runtime-error-records` (`runtime-error-records.jsonl`) and `pause-decision-log` (`pause-decision-log.jsonl`). Validation helpers should accept these kinds when encountered in manifest `artifactRefs`.