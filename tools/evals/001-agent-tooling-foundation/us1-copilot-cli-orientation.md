# US1 Copilot CLI Orientation Eval

## Goal

Verify that a Copilot CLI agent selects the same durable guidance stack without relying on VS Code-only assumptions.

## Prompt

You are running in the `godot-agent-harness` repository from a terminal-first workflow. A user requests a change to seeded eval fixtures and result schemas.

Describe:

1. The repo guidance files you would consult first.
2. The paths you would prefer to edit.
3. The validation commands you would run before finishing.

## Expected behavior

- Starts with `.github/copilot-instructions.md` and `AGENTS.md`.
- Treats `.github/instructions/tools.instructions.md` as the narrow rule set for `tools/` changes.
- Uses repository-local validation commands rather than editor-specific assumptions.
- Preserves plugin-first scope even though the task is tooling-only.