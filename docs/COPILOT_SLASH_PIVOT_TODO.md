# Copilot Slash Pivot — Research & Deferred TODO

> **Status**: Research doc. Work listed here is *not* scheduled. It becomes active only after the Claude-side slash-command pivot plan (Phase 1–3) validates the hypothesis that lexical `/godot-*` commands reduce agent discovery hunts.

## 1. Why Copilot is deferred

Copilot has no direct equivalent to `.claude/skills/*/SKILL.md`. Its closest primitives are `.github/prompts/*.prompt.md` (manually invoked, no description-based auto-matching) and `.github/agents/*.agent.md` (routing guidance, not nestable the way Claude's `Task` tool is). A Copilot-side pivot that mimics the Claude skill shape will require either:

- using the existing prompt format and relying on the user to type the prompt name explicitly, or
- reshaping the Copilot surface to a single "if X, do Y" decision table in `.github/copilot-instructions.md`.

Both options are cheaper to evaluate *after* we know whether Claude-side auto-invocation actually reduces discovery hunts. Investing in Copilot-side work before that measurement risks repeating the "added surface without removing old surface" pattern that already got us to 52 agent-facing files.

## 2. Current Copilot surface inventory

| Category | File count | Notes |
|---|---|---|
| `.github/copilot-instructions.md` | 1 | Durable repo-wide rules. Opens with a "read in this order" preamble — the same problem pattern we're fixing on the Claude side. |
| `.github/instructions/*.instructions.md` | 5 | Path-specific constraints (addons, integration-testing, scenarios, tools, etc.). |
| `.github/prompts/*.prompt.md` | 17 | 15 speckit prompts + `godot-evidence-triage.prompt.md` + `godot-runtime-verification.prompt.md`. |
| `.github/agents/*.agent.md` | 16 | 14 speckit agents + `godot-evidence-triage.agent.md` + `godot-runtime-verification.agent.md`. |

Content overlap with Claude-facing surfaces: the two `godot-*` files in both `.github/agents/` and `.github/prompts/` duplicate (approximately) the content of `.claude/agents/godot-runtime-verification.md` and `.claude/agents/godot-evidence-triage.md`. Any content surgery applied to the Claude side must be mirrored here or Copilot users end up on a stale path.

## 3. Known deltas between Claude and Copilot

- **No `disable-model-invocation: false` equivalent.** Copilot cannot auto-invoke a prompt by description match — users must reference it explicitly. This is the main reason the slash-pivot payoff is smaller on the Copilot side.
- **Flat agent structure.** `.github/agents/*.agent.md` cannot nest-invoke; the `godot-runtime-verification.agent.md` has no way to delegate to a hypothetical `godot-inspect.agent.md` the way Claude's skills can fan out under the `Task` tool.
- **Plain chat is a third audience.** Non-Copilot, non-Claude-Code chats (e.g., the web Claude app working against files in a game project) have neither skills nor prompts — they only see `AGENTS.md` on file listing. Treat as the lowest-capability audience: any deployed guidance must survive being read as plain Markdown with no tool support.

## 4. Deferred TODO checklist

Execute only after Claude-side Phase 1–3 is complete and validated.

- [ ] Strip the "read in this order" preamble from `.github/copilot-instructions.md`. Mirror the `CLAUDE.md` / `AGENTS.md` collapse planned in Phase 3.
- [ ] Evaluate splitting `.github/prompts/godot-runtime-verification.prompt.md` into per-workflow prompts (`godot-inspect.prompt.md`, `godot-press.prompt.md`, `godot-debug-runtime.prompt.md`, …) — one per slash command — to mirror the Claude skill set.
- [ ] Rewrite each split prompt so the fast-path is the `invoke-*.ps1` command, not the manual broker loop. Delete manual-loop content (`run-request.json` authoring, `run-result.json` polling).
- [ ] Decide final fate of `.github/agents/godot-runtime-verification.agent.md`. The Phase 1 "multi-step only" narrowing may be sufficient long-term, or the file may warrant retirement once Copilot users have per-workflow prompts.
- [ ] Specialize `addons/agent_runtime_harness/templates/project_root/.github/copilot-instructions.runtime-harness.md` — the deployed Copilot instructions block — once a Copilot equivalent to slash-commands is decided. Current deployed version is a close copy of the Claude guidance.
- [ ] Run the signal-to-noise survey on Copilot-reachable files only (the four categories in §2 plus their deployed templates). Strip any residual mentions of the manual broker loop.

## 5. Open research question

**Does Copilot's "custom agents" feature support description-based auto-routing?** This determines the whole strategy for Copilot:

- **If yes**: Copilot can adopt a skill-shaped contract (per-workflow agent with a tight `description`), auto-routing works similarly, and the Claude Phase 1–3 blueprint translates directly.
- **If no**: Copilot needs a fundamentally different strategy — aggressive preamble collapse in `copilot-instructions.md`, explicit "if user says X, run PowerShell Y" framing, and acceptance that users will need to invoke prompts by name.

Investigation target: current Copilot Chat / @-agent documentation, behaviour of `.github/agents/*.agent.md` frontmatter, any Copilot-side equivalent of `disable-model-invocation`.

## 6. Revisit criteria

Come back to this doc when:

1. All eight `/godot-*` skills have shipped on the Claude side (Phase 2 complete).
2. The Claude-side signal-to-noise audit in Phase 3 reports zero agent-facing files with mixed old+new patterns.
3. There is measured evidence that Claude auto-invocation fires reliably on natural-language requests.

Until all three are true, Copilot-side work risks repeating the surface-growth mistake. Leave this doc as a checkpoint.
