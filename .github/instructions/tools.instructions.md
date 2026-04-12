---
applyTo: "tools/**"
---

# Tools Instructions

- Keep scripts deterministic and repo-local. Accept repository-relative paths unless an absolute path is required.
- Emit machine-readable JSON for validation and result files whenever another tool or agent will consume the output.
- Reuse repository schemas from `tools/evals/`, `tools/automation/`, and `specs/001-agent-tooling-foundation/contracts/` instead of inventing one-off JSON shapes.
- Place eval prompts and result files in `tools/evals/`, evidence helpers in `tools/evidence/`, and automation contracts or logs in `tools/automation/`.
- Do not hide side effects. Scripts that write files should make the output path explicit.