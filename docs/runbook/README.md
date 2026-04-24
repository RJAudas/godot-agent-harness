# Runbook Recipes — Migrated to Skills

All per-workflow recipe files in this directory have been consolidated into Claude Code skills under [`.claude/skills/`](../../.claude/skills/). Use the table below to find the matching skill.

| Workflow | Skill |
|---|---|
| Scene inspection | [godot-inspect](../../.claude/skills/godot-inspect/SKILL.md) |
| Input dispatch | [godot-press](../../.claude/skills/godot-press/SKILL.md) |
| Behavior watch | [godot-watch](../../.claude/skills/godot-watch/SKILL.md) |
| Build-error triage | [godot-debug-build](../../.claude/skills/godot-debug-build/SKILL.md) |
| Runtime-error triage | [godot-debug-runtime](../../.claude/skills/godot-debug-runtime/SKILL.md) |
| Pin run | [godot-pin](../../.claude/skills/godot-pin/SKILL.md) |
| Unpin run | [godot-unpin](../../.claude/skills/godot-unpin/SKILL.md) |
| List pinned runs | [godot-pins](../../.claude/skills/godot-pins/SKILL.md) |

## For non-Claude tools

The underlying `invoke-*.ps1` scripts in [`tools/automation/`](../../tools/automation/) are unchanged and remain the canonical entry points for Copilot, CI, and any other consumer. Each skill body documents the equivalent shell command.
