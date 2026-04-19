# Quickstart: Autonomous Editor Evidence Loop

## Goal

Validate that an agent can trigger an autonomous editor run for the example project, persist and validate the resulting scenegraph evidence bundle, and receive a machine-readable result without any dock interaction after the request is issued.

## 1. Prepare the Example Project

1. Open `examples/pong-testbed/` in the Godot editor once the feature implementation is present.
2. Enable the harness addon and confirm the Scenegraph Harness plugin loads normally.
3. Use the one-time `Deploy Agent Assets` action so the project receives the required harness templates and automation-facing assets.
4. Confirm the project has a valid `harness/inspection-run-config.json` and the example scenes needed for healthy and failing runs.

## 2. Validate Capability Detection

1. From the workspace, run `pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot examples/pong-testbed`.
2. Confirm the result reports exactly one eligible open project and marks launch, capture, persistence, validation, and shutdown control as ready.
3. Confirm the capability check returns a blocked result instead of guessing if prerequisites are missing or the target is ambiguous.

## 3. Validate A Healthy Autonomous Run

1. Submit a machine-readable automated run request with `pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot examples/pong-testbed -RequestFixturePath examples/pong-testbed/harness/automation/requests/run-request.healthy.json`.
2. Confirm the plugin starts a play session in the open editor without requiring a play-button click.
3. Confirm the runtime session attaches, the harness captures a scenegraph snapshot, and the latest bundle is persisted.
4. Confirm the run performs manifest and artifact validation before reporting success.
5. Confirm the play session stops automatically after validation finishes.

## 4. Validate Result And Evidence Handoff

1. Inspect the final automated run result artifact from the workspace.
2. Confirm it reports the run identifier, manifest path, output directory, validation outcome, and termination status.
3. Open the reported manifest and confirm the referenced snapshot, diagnostics, and summary artifacts exist.
4. Validate the manifest with `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>` if helper tooling remains unchanged.

## 5. Validate Failure And Blocked Cases

1. Submit a run against an intentionally broken expectation case and confirm the final result classifies the failure correctly while still returning the persisted evidence path.
2. Trigger a blocked prerequisite condition, such as missing harness wiring or ambiguous target detection, and confirm the capability or run result reports `blocked` rather than a misleading runtime failure.
3. Submit a second request while one autonomous run is already active and confirm the system returns a machine-readable blocked result instead of queueing silently.
4. Confirm stale artifacts from a previous run are not misreported as the output of the current request.

## Current Validation Status

- Schema, fixture, helper-script, and manifest-backed PowerShell validation for the brokered path is implemented and covered by `pwsh ./tools/tests/run-tool-tests.ps1`.
- Live Godot editor execution still has to be performed manually against an open `examples/pong-testbed/` session to satisfy the full end-to-end quickstart.

## Exit Criteria

- The open Godot editor can accept an autonomous run request from the workspace without manual dock interaction after the request is issued.
- The automation loop produces a machine-readable capability result, lifecycle-aware final result, and a validated manifest-centered evidence bundle.
- Healthy, blocked, and failing runs are distinguishable from their machine-readable outputs alone.
- The play session stops automatically after the required evidence has been captured and validated.
- Repeated run validation demonstrates the loop can meet the target success rate and end-to-end timing expectations for the seeded example flow.