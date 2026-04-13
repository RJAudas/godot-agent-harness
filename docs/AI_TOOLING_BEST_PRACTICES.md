# AI Tooling Best Practices

This note collects practical guidance for adding agent tooling to this repository.
It focuses on three asset types:

- agents: multi-step workers that can plan, call tools, and iterate
- instructions: stable guidance files that shape agent behavior in this repo
- skills: reusable bundles of process knowledge or capability-specific instructions

The goal is to keep future tooling predictable, inspectable, and easy to evolve.

## How To Use This Doc

Use this document when deciding:

- whether a feature should be a workflow, an agent, an instruction file, or a skill
- where to store agent guidance in this repository
- what information belongs in repo-level guidance versus reusable capability bundles
- what safety and validation requirements should exist before giving an agent more autonomy

## Adopted guidance stack

This repository now uses the following layers as the primary agent-tooling entry points:

- `.github/copilot-instructions.md` for repo-wide Copilot guidance
- `AGENTS.md` for agent-facing operating rules
- `.github/instructions/*.instructions.md` for path-specific constraints
- `.github/prompts/` and `.github/agents/` for Copilot-native reusable workflows

Use this document to decide when new behavior belongs in one of those layers, not as a replacement for them.

## Copilot-First Recommendations

Treat GitHub Copilot documentation as the canonical source for file placement and instruction precedence in this repository.
Use Anthropic guidance to improve authoring quality, workflow design, and validation discipline, not to replace Copilot's file model.

### Create now: .github/copilot-instructions.md

Why:

- this is the clearest repo-wide customization point documented for Copilot
- it reduces repeated repo exploration for every future agent session
- it is the best place for durable build, validation, and layout facts
- it should stay small enough that always-applicable context remains high-signal

How:

1. summarize the repository purpose, layout, and validation rules
2. include only stable guidance that should apply across most tasks
3. document real commands only after validating them locally
4. keep it concise enough to stay maintainable and useful when automatically included
5. move bulky reference material into docs, AGENTS.md, or path-specific instructions instead of turning repo instructions into a knowledge dump

### Create now: AGENTS.md at repo root

Why:

- it complements README content with agent-focused operating guidance
- it is useful beyond Copilot and aligns with the emerging cross-agent convention
- it is a good place for execution rules, testing expectations, and working norms that are too agent-specific for README

How:

1. keep README focused on humans and AGENTS.md focused on coding agents
2. include practical rules such as where to look first, what to validate, and what paths to avoid touching casually
3. add nested AGENTS.md files only after a subtree has genuinely different rules

### Create selectively: path-specific instruction files

Why:

- Copilot supports them directly
- they reduce conflicts by scoping rules to the files that need them
- they are better than stuffing every exception into one repo-wide file

How:

1. create them only where a subtree has materially different rules
2. keep the applyTo scope narrow and explicit
3. do not duplicate large chunks of repo-wide guidance unless the subtree needs stricter overrides

### Create later: local skills

Why:

- Copilot does not currently provide the same first-class hosted skill model described in Claude and OpenAI docs
- local skills are still useful as reusable capability bundles, especially if this project later uses other agent runtimes or MCP-connected tooling
- the skill pattern is strongest when a workflow has already repeated enough to deserve packaging

How:

1. treat skills as internal reusable process bundles, not assumed Copilot runtime features
2. package a narrow workflow with a SKILL.md plus supporting references or scripts
3. add a skill only after you can name the repeated failure it prevents or the repeated task it accelerates

## Gaps Filled By Anthropic Guidance

Copilot documentation is strong on where instructions live and how they apply.
The Anthropic material fills in several authoring and validation gaps that are still useful here:

- how much autonomy to grant: start with workflows and only move to agents when the path is not predictable
- how to write reusable skills: keep them concise, narrowly scoped, and discoverable by strong names and descriptions
- how to structure larger skills: use progressive disclosure and one-level-deep references from SKILL.md
- how to improve quality: build evaluations before over-documenting, then iterate from observed failures
- how to make tools usable: invest in agent-computer interface design, examples, and error-resistant parameter choices

What does not map one-to-one:

- Claude Skill loading and hosted execution behavior should not be assumed to exist in Copilot
- model-specific testing advice for Haiku, Sonnet, and Opus does not transfer directly, but the principle of testing across the models you plan to use still holds
- Claude-specific skill metadata constraints are informative for naming discipline, even if they are not enforced by Copilot

## Core Principles

### 1. Start simpler than you think

Prefer the least autonomous pattern that solves the job:

1. single prompt with strong context
2. prompt plus retrieval or structured examples
3. fixed workflow with explicit steps
4. routed or multi-agent workflow
5. open-ended agent loop

Use a true agent only when the path cannot be reliably hardcoded ahead of time.
Open-ended autonomy raises cost, latency, and the chance of compounding errors.

### 2. Treat tool interfaces as product surfaces

Most agent failures come from unclear tool contracts, not just weak top-level prompts.
Tool names, parameters, examples, and boundary rules should read like well-written API docs for a new teammate.

Design tools so they are:

- obvious to choose between
- hard to misuse
- easy to validate from machine-readable output
- explicit about side effects and approval requirements

### 3. Keep guidance layered and non-conflicting

Separate stable rules from task-specific requests.

- repo-wide instructions should capture durable project facts and validation rules
- path-specific instructions should narrow behavior for a file type or subsystem
- AGENTS.md should provide agent-facing working context near the code being changed
- skills should package reusable processes that can be invoked across tasks

If two guidance layers disagree, quality drops quickly. Avoid overlap unless one layer is intentionally more specific.

### 4. Require ground truth, not vibes

Agents should make decisions from observable evidence:

- command output
- tests
- traces
- structured logs
- deterministic scenario results

For this repository, that aligns directly with the runtime-evidence goal of the harness itself.

### 5. Evals are part of the feature

Prompt and agent changes should be treated like code changes.
If a new agent, instruction set, or skill matters, define a validation loop for it.

Examples:

- golden prompt-response cases
- scenario runs with expected pass or fail output
- tool-selection checks
- regression tasks drawn from real repository work

## Agents

### When to create an agent

Create an agent when the work is open-ended and the number or order of steps is not predictable.
Examples that fit this repo:

- investigating multi-file Godot harness failures
- collecting evidence across scenario outputs, traces, and logs
- coordinating search, design, and code changes across addon and scenario assets

Do not create an agent when a deterministic script or fixed workflow is enough.

### Recommended agent design

Each agent should have:

- one clear owner job
- explicit input contract
- explicit stopping conditions
- limited tool access
- approval checkpoints for destructive or high-impact actions
- observable output that another human or agent can verify

Good agent prompts usually specify:

- mission
- constraints
- allowed tools or environments
- expected output shape
- escalation behavior when blocked

### Recommended agent patterns

- prompt chain: for fixed sequential work like outline -> review -> artifact
- routing: for different request classes that need different specialists
- orchestrator-workers: for complex repo work where subtasks are unknown up front
- evaluator-optimizer: for artifact refinement when quality criteria are clear

For this repo, orchestrator-workers and evaluator-optimizer are the most likely patterns to pay off.

### Agent safety rules

- sandbox tool execution where possible
- cap iteration counts
- require approval before writes outside expected paths
- log tool calls and outcomes
- prefer structured outputs over freeform summaries when another machine will consume the result

## Instructions

### What belongs in instructions

Instructions should contain stable operating guidance, not per-ticket intent.
Good instruction content includes:

- repository purpose and architecture map
- build, test, lint, and validation commands
- directory ownership and file-placement rules
- style and review expectations
- known failure modes and required workarounds
- what to trust first before searching more broadly
- validation routing rules that should apply on most tasks, such as when to use ordinary tests versus Scenegraph Harness runtime verification

Repo-wide instruction files are a poor place for exhaustive reference material.
Because this guidance may be attached broadly, large instruction files create noisy context and can lower signal quality.
Prefer concise rules in repo-wide instructions and put bulk detail into regular docs, AGENTS.md, or path-scoped instruction files.

### What does not belong in instructions

- temporary feature requirements
- issue-specific acceptance criteria
- long tutorial content better kept in docs
- duplicated rules that already live in a more specific instruction layer

### Formatting guidance

Write instructions in a structure the model can parse easily:

1. identity or purpose
2. durable rules
3. examples or patterns
4. project context
5. validation expectations

Use short headings, flat lists, and concrete commands.
Prefer exact file paths, exact command names, and exact success criteria over prose-heavy advice.

### Validation routing for this repo

For this repository, the validation taxonomy itself belongs in instructions and `AGENTS.md`:

- ordinary tests
- Scenegraph Harness runtime verification
- combined validation

That routing rule is durable and should not be buried only inside a reusable prompt.
The reusable prompt and agent layer should then carry the end-to-end runtime-verification workflow after the routing decision is made.
Keep manifest-centered evidence triage separate so post-run diagnosis does not become overloaded with capability checks and run orchestration.

### Suggested instruction layout for this repo

- .github/copilot-instructions.md
  - repo-wide goals, structure, validation, and safety defaults
- .github/instructions/*.instructions.md
  - path-specific rules for addon code, docs, scenarios, and tools
- AGENTS.md at repo root
  - shared agent-facing build and workflow guidance
- nested AGENTS.md files later if subprojects diverge

### Instruction authoring checklist

- keep it under active maintenance
- document commands only after validating them
- call out prerequisites and ordering constraints
- prefer facts over aspirational statements
- remove stale guidance aggressively

## Skills

### Copilot compatibility note

Skills are the least one-to-one concept here.
Copilot clearly documents repository instructions, path-specific instructions, and AGENTS.md behavior.
It does not give this repository the same documented hosted skill mechanism described in Claude docs.

For this repo, use a local skill pattern only when you want a reusable, tool-adjacent capability bundle that may later be consumed by non-Copilot agent runtimes, local shells, or MCP-oriented workflows.

### What a skill should be

A skill should package reusable know-how, not a one-off task.
Good skill candidates for this repository include:

- scenario-trace analysis
- Godot addon debugging workflow
- structured repro extraction from issue text
- deterministic scenario authoring checklist

### What a skill should contain

At minimum:

- clear name
- short description that helps the model know when to use it
- SKILL.md with explicit instructions
- any supporting files, templates, or scripts that make the workflow real

Keep each skill narrow. If a skill does three unrelated jobs, discovery and reuse get worse.

### Skill design rules

- version skills deliberately
- describe the trigger conditions for using the skill
- include examples, edge cases, and output format expectations
- keep supporting files close to the SKILL.md manifest
- review skills as privileged instructions before enabling them

Additional guidance validated by Anthropic's skill authoring guidance:

- keep SKILL.md concise and avoid teaching basic concepts the model already knows
- choose the right degree of freedom: exact steps for fragile operations, looser heuristics for open-ended analysis
- use descriptive names and descriptions that say both what the skill does and when to use it
- prefer forward slashes in file paths for portability
- keep references one level deep from SKILL.md
- move bulky detail into clearly named reference files rather than one giant manifest
- provide utility scripts for deterministic operations instead of asking the model to regenerate them each time
- build validator loops such as plan -> validate -> execute -> verify for high-risk operations

### How to create a local skill here

1. identify a repeated workflow where the current agent repeatedly needs the same context, rules, or scripts
2. write three evaluation scenarios that expose the current gap before writing much documentation
3. create a narrow directory under a future skills/ folder
4. write a short SKILL.md that states what the skill does, when to use it, and where extra details live
5. put detailed references in sibling files directly linked from SKILL.md
6. add scripts only for deterministic operations that are safer or faster than regenerated code
7. test with real tasks, observe failures, and refine from evidence

### Skill safety rules

Treat every skill as privileged code plus privileged prompt content.

- do not expose arbitrary skill selection to untrusted end users
- gate write actions and networked actions behind policy or approval checks
- prefer local execution when data residency or retention matters
- inspect skill contents before mounting them into runtime environments

## Repository-Specific Recommendations

If you are about to add agent tooling here, start with this sequence:

1. add one repo-level instruction file that explains project layout and validation
2. add one root AGENTS.md with agent-facing working rules
3. add path-specific instructions only where a subtree truly differs
4. introduce skills only after a reusable workflow appears at least twice
5. add eval fixtures or deterministic checks before expanding autonomy

This is the practical order of value for this repository:

1. repo-wide Copilot instructions
2. root AGENTS.md
3. path-specific instructions for clearly different subtrees
4. local skills only for repeated, validated workflows

For this repository in particular:

- tie agent outputs to machine-readable runtime evidence wherever possible
- keep Godot-specific API references in docs, not inside every prompt
- prefer plugin-first and scenario-driven validation language, matching the constitution
- keep the validation split explicit: instructions choose between ordinary tests, runtime verification, and combined validation, while prompt and agent artifacts execute the chosen workflow
- document any requirement to inspect sibling checkouts such as ../godot only when truly needed

## Validation Heuristics

Before creating a new agent artifact, ask these questions:

- Is this a stable rule or a one-off task?
  - stable rule: put it in instructions or AGENTS.md
  - one-off task: keep it in the task prompt
- Does this need path-specific behavior?
  - if yes, prefer a scoped instruction file over repo-wide exceptions
- Has this workflow repeated often enough to deserve packaging?
  - if yes, consider a skill or utility script bundle
- Can success be measured mechanically?
  - if no, add a validator, checklist, or scenario before increasing autonomy
- Does the proposed artifact rely on a runtime feature Copilot does not document?
  - if yes, treat it as a local convention, not a guaranteed platform behavior

## Suggested Future Layout

```text
.github/
  copilot-instructions.md
  instructions/
    addon.instructions.md
    docs.instructions.md
    scenarios.instructions.md
AGENTS.md
skills/
  scenario-trace-analysis/
    SKILL.md
  godot-addon-debugging/
    SKILL.md
docs/
  AI_TOOLING_BEST_PRACTICES.md
```

## Source Refrains

No copyrighted song lyrics are included here.
Instead, these short original refrains act as source mnemonics for where the guidance came from.

- "Start with the smallest loop, then add autonomy when fixed paths break." Inspired by Anthropic's guidance on using the simplest workable pattern first.
- "Write the rules where the agent works, and keep the nearest guidance in charge." Inspired by GitHub and AGENTS.md guidance on repository, path-specific, and nearest-file instructions.
- "Bundle repeatable know-how, name it cleanly, and treat it like privileged code." Inspired by OpenAI's Skills guidance.
- "If the agent cannot prove it from output, logs, or tests, it has not learned enough yet." Inspired by agent observability and evaluation guidance across sources.

## Sources

- Anthropic, "Building effective agents" (Dec 19, 2024)
- OpenAI Developers, "Agents SDK"
- OpenAI Developers, "Prompt engineering"
- OpenAI Developers, "Skills"
- GitHub Docs, "Adding repository custom instructions for GitHub Copilot"
- GitHub Docs, "Adding personal custom instructions for GitHub Copilot"
- AGENTS.md, "A simple, open format for guiding coding agents"
- Anthropic Docs, "Skill authoring best practices"

## Source Notes

### Anthropic: Building effective agents

Used for:

- decision framework for when to use workflows versus agents
- emphasis on simplicity, transparency, and tool design
- workflow pattern vocabulary such as routing and evaluator-optimizer

### OpenAI: Agents SDK

Used for:

- agent responsibilities around orchestration, tools, state, approvals, and observability
- dividing concerns between one specialist and multi-agent orchestration

### OpenAI: Prompt engineering

Used for:

- structured instruction writing
- message role separation
- examples, context placement, and evaluation discipline

### OpenAI: Skills

Used for:

- definition of versioned reusable skill bundles
- skill discoverability via name and description
- safety guidance for treating skills as privileged instructions

### GitHub Docs: custom instructions

Used for:

- repository-wide versus path-specific instruction layout
- instruction precedence and practical file placement

### AGENTS.md

Used for:

- rationale for separating human README content from agent-facing operating guidance
- nearest-file precedence model for multi-project repos

### Anthropic Docs: Skill authoring best practices

Used for:

- concise skill writing and progressive disclosure
- naming and description quality for skill discovery
- workflow checklists and validation loops
- testing and iteration guidance based on observed usage
