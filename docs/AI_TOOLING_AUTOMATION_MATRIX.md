# AI Tooling Automation Matrix

## Purpose

Use this matrix to decide whether a repository concern belongs in instructions, a fixed workflow, a Copilot-native prompt or agent, or a future local skill.

| Need | Best fit | Why | Validation requirement |
|------|----------|-----|------------------------|
| Durable repo or subtree rule | Instructions | Stable guidance should be attached close to the files it governs. | Confirm the rule is concise, non-conflicting, and points to real paths. |
| Deterministic local operation | Scripted workflow | Fixed steps are cheaper and safer than an open-ended agent loop. | Validate output shape and exit behavior locally. |
| Repeated human-invoked diagnosis or drafting task | Prompt artifact | The user chooses when to invoke it and reviews the output. | Seed at least one prompt fixture and expected output. |
| Open-ended multi-step repo task with clear scope | Agent artifact | The artifact can plan, inspect, and iterate when the exact path is not predictable. | Define scope, stop conditions, output shape, and write boundary. |
| Reusable cross-runtime capability bundle | Local skill | Package repeated know-how only after the workflow proves reusable. | Show repeated demand and deterministic supporting assets. |

## Decision rules for this repository

- Prefer instructions for rules that should apply on most tasks or across a subtree.
- Prefer scripts for contract validation, manifest assembly, and other deterministic operations.
- Use prompt artifacts for guided evidence triage where a human still chooses whether to run the workflow.
- Use agent artifacts only when the repo task is open-ended enough to justify planning and tool iteration.
- Defer local skills until the same workflow repeats across multiple tasks or runtimes.

## Safety rules

- Every autonomous artifact must declare a write boundary before it is treated as approval-free.
- Machine-readable run logs are required for autonomous actions.
- If the task requires engine-facing or destructive changes, escalate instead of expanding the boundary informally.