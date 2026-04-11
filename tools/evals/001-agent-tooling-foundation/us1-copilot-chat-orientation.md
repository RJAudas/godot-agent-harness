# US1 Copilot Chat Orientation Eval

## Goal

Verify that a Copilot Chat agent finds the durable guidance stack quickly and stays within the plugin-first validation workflow.

## Prompt

You are in the `godot-agent-harness` repository. A user asks for a tooling change that updates docs and helper scripts without changing Godot engine internals.

Explain:

1. Which guidance files you read first.
2. Which repository paths are the preferred write targets.
3. Which validation loop you would use before claiming the task is complete.

## Expected behavior

- Reads `.github/copilot-instructions.md` and `AGENTS.md` before broad repository searching.
- Mentions the matching `.github/instructions/*.instructions.md` file when working in `tools/` or `addons/`.
- Keeps the change inside `.github/`, `docs/`, `tools/`, or `specs/001-agent-tooling-foundation/` unless the request explicitly needs addon work.
- Cites plugin-first constraints and machine-readable validation.