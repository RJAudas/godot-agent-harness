# Agent Tooling Foundation Guide

This document explains the agent tooling added to this repository, what it is for, and how to use it manually when you want direct control instead of relying on automatic discovery.

## Manual entry points

These are the main scripts and artifact locations a developer can use directly.

### Deploy the harness into another Godot game project

```powershell
pwsh ./tools/deploy-game-harness.ps1 -GameRoot <game-root>
```

Use this when you want to install the addon plus the project-level Copilot and harness assets into another local Godot game from this repository checkout.

### Validate a JSON file against a schema

```powershell
pwsh ./tools/validate-json.ps1 -InputPath <json-path> -SchemaPath <schema-path>
```

Use this for eval result files, automation contracts, and any repository JSON fixture that should conform to a schema.

### Generate an evidence manifest from a runtime artifact directory

```powershell
pwsh ./tools/evidence/new-evidence-manifest.ps1
```

By default this uses the seeded sample bundle under `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/` and writes `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.generated.json`.

### Validate an evidence manifest and its referenced files

```powershell
pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>
```

Use this after a plugin or scenario run produces runtime artifacts and a manifest.

### Check whether an autonomous artifact may edit a path

```powershell
pwsh ./tools/automation/validate-write-boundary.ps1 -ArtifactId <artifact-id> -RequestedPath <path> -RequestedEditType <edit-type>
```

Use this before allowing a prompt or agent workflow to write files autonomously.

### Create a machine-readable autonomous run record

```powershell
pwsh ./tools/automation/new-autonomous-run-record.ps1 -ArtifactId <artifact-id> -WriteBoundaryId <boundary-id> -RequestSummary <summary>
```

Use this when you want an auditable JSON record of what an automation flow attempted and whether it stayed within its declared boundary.

### Read the current editor-evidence capability artifact

```powershell
pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot <game-root>
```

Use this when the Godot project is already open in the editor and you want a deterministic read of the latest capability artifact that the plugin-owned broker wrote.

### Write an autonomous editor-evidence run request

```powershell
pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot <game-root> -RequestFixturePath <fixture-path>
```

Use this when you want to submit a machine-readable request into the plugin-owned file broker without editing the request JSON by hand.

### Run the automated PowerShell tool tests

```powershell
pwsh ./tools/tests/run-tool-tests.ps1
```

Use this to execute the Pester-based contract suite for every PowerShell script under `tools/`.

## What this tooling is for

The tooling foundation exists to make future plugin work easier to specify, validate, and consume.

It provides:

- a layered guidance stack for agents working in this repository
- seeded eval prompts and expected outputs so agent behavior can be measured
- evidence bundle contracts so runtime data has a stable handoff format
- boundary checks and run logs for any approval-free automation

It does **not** implement runtime harness behavior by itself.

It now does provide the workspace-side helper surface for the autonomous editor evidence loop:

- read capability artifacts from `harness/automation/results/`
- write run requests into `harness/automation/requests/`
- validate the resulting run-result and manifest-centered evidence artifacts with the existing schema and manifest tools

If you want collision events, frame traces, scene snapshots, or other runtime data streams, those still need to be implemented in `addons/agent_runtime_harness/` or another runtime-facing part of the repo. The tooling here helps define what those outputs should look like and how to validate them once they exist.

## Repo map

### Guidance and reusable agent assets

- `.github/copilot-instructions.md`: durable repo-wide Copilot guidance
- `AGENTS.md`: agent-facing operating rules for the repository
- `.github/instructions/`: path-specific instruction files
- `.github/prompts/`: reusable prompt artifacts
- `.github/agents/`: reusable agent artifacts

### Validation and support scripts

- `tools/validate-json.ps1`: generic schema validation for repository JSON files
- `tools/evidence/`: evidence manifest assembly and validation
- `tools/automation/`: write-boundary validation, contracts, and run records

### Seeded evals and fixtures

- `tools/evals/001-agent-tooling-foundation/`: story-specific eval prompts and result files
- `tools/evals/fixtures/001-agent-tooling-foundation/`: reusable sample evidence inputs

## Automatic versus manual use

Most of this tooling is designed to be automatically discovered by an agent.

Examples:

- an agent reads `.github/copilot-instructions.md` and `AGENTS.md` without you needing to point to them every time
- seeded eval prompts and expected results give the agent a prepared test surface
- schemas and validation scripts give the agent a repeatable way to prove its outputs are well-formed

But developers still have agency and can use the tooling manually when needed.

The current harness also supports plugin-driven asset deployment from inside Godot itself.

Recommended deployment flow for a fresh game project:

1. Copy `addons/agent_runtime_harness/` into the game project.
2. Enable the addon in Godot.
3. Click `Deploy Agent Assets` in the Scenegraph Harness dock.

That flow installs the same `.github/`, `AGENTS.md`, `harness/`, and `project.godot` wiring that the PowerShell deployment script installs from the source repository.

Examples:

- run a validator yourself before trusting a generated JSON file
- assemble a manifest from runtime artifacts before asking an agent to diagnose a failure
- check a write boundary yourself before letting an automation artifact write files
- inspect or author eval fixtures directly when you want to tighten the workflow

## How this helps build plugin functionality

The value is in reducing ambiguity around future runtime-facing work.

For example, if you want to expose collision events for agent consumption:

1. Implement the actual collision-event stream in `addons/agent_runtime_harness/`.
2. Have the runtime or scenario flow write a structured artifact such as `events.json`.
3. Reference that artifact from an evidence manifest.
4. Validate the manifest and referenced files with the scripts in `tools/evidence/`.
5. Add or update eval fixtures under `tools/evals/` so another agent can prove it can consume the new event stream.

That means the tooling does not replace plugin implementation. It gives you a contract, validation loop, and eval surface around the plugin feature once you build it.

The deployment feature added to the addon follows the same principle. The addon now carries its own installable agent-asset templates under `addons/agent_runtime_harness/templates/project_root/`, and both deployment paths reuse that same template source:

- the Godot plugin deploys those assets directly into the active game project
- `tools/deploy-game-harness.ps1` deploys those same assets from the source checkout

That keeps the plugin self-sufficient after it has been copied into another game project while still preserving a deterministic source-driven installer for local development and testing.

## Recommended manual workflows

### When adding or changing a plugin-facing data output

1. Implement the runtime behavior under `addons/agent_runtime_harness/`.
2. Capture the raw runtime artifact in a deterministic scenario run.
3. Assemble or update an evidence manifest.
4. Validate the manifest.
5. Add or update eval fixtures that describe how an agent should consume the new artifact.

### When authoring a new prompt or agent artifact

1. Add or update the prompt or agent under `.github/prompts/` or `.github/agents/`.
2. Add a seeded eval prompt and an expected result under `tools/evals/001-agent-tooling-foundation/`.
3. Validate any JSON output files with `tools/validate-json.ps1`.
4. If the artifact may write files autonomously, declare and validate its write boundary first.

### When reviewing automation safety

1. Inspect `tools/automation/write-boundaries.json`.
2. Validate the requested write path with `tools/automation/validate-write-boundary.ps1`.
3. Emit a run record with `tools/automation/new-autonomous-run-record.ps1` when the flow executes.

## Quick reference files

- `docs/AI_TOOLING_BEST_PRACTICES.md` explains when to use instructions, prompts, agents, and future skills.
- `docs/AI_TOOLING_AUTOMATION_MATRIX.md` explains the decision rules behind automation artifact choices.
- `specs/001-agent-tooling-foundation/quickstart.md` shows the implemented validation flow for the current feature.