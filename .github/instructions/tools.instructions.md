---
applyTo: "tools/**"
---

# Tools Instructions

- Keep scripts deterministic and repo-local. Accept repository-relative paths unless an absolute path is required.
- Emit machine-readable JSON for validation and result files whenever another tool or agent will consume the output.
- Reuse repository schemas from `tools/evals/`, `tools/automation/`, and `specs/001-agent-tooling-foundation/contracts/` instead of inventing one-off JSON shapes.
- Place eval prompts and result files in `tools/evals/`, evidence helpers in `tools/evidence/`, and automation contracts or logs in `tools/automation/`.
- Do not hide side effects. Scripts that write files should make the output path explicit.
- `tools/automation/submit-pause-decision.ps1` writes a validated `pause-decision.json` into `harness/automation/requests/` inside a live integration-testing project root. Keep it aligned with `specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json`.
- New artifact kinds from specs/007 are `runtime-error-records` (`runtime-error-records.jsonl`) and `pause-decision-log` (`pause-decision-log.jsonl`). Validation helpers should accept these kinds when encountered in manifest `artifactRefs`.