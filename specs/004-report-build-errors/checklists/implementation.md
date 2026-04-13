# Implementation Checklist: Report Build Errors On Run

**Purpose**: Track implementation and validation work for build-failure reporting across the automation broker, shared contracts, and deterministic validation surfaces.
**Created**: 2026-04-12
**Feature**: [spec.md](../spec.md)

**Note**: This checklist is generated from the current feature specification, implementation plan, data model, and quickstart guidance.

## Broker Detection And Classification

- [ ] CHK001 Detect editor-reported build, parse, and blocking resource-load failures before runtime attachment completes.
- [ ] CHK002 Add a distinct `build` failure classification without regressing existing blocked, launch, attachment, capture, validation, shutdown, or gameplay outcomes.
- [ ] CHK003 Attribute every reported build failure to the active `requestId` and `runId`.
- [ ] CHK004 Emit build-failure information through lifecycle status before or alongside the final failed run result.
- [ ] CHK005 Preserve the existing successful-run flow when no build failure occurs.

## Result Contract And Payload Shape

- [ ] CHK006 Extend the shared automation run-result contract so build-failed runs are machine-readable and deterministic.
- [ ] CHK007 Include normalized diagnostic fields for affected resource, message, severity, and optional line and column.
- [ ] CHK008 Include the raw editor build-output snippet in the failed run result.
- [ ] CHK009 Define explicit no-manifest semantics for build-failed runs.
- [ ] CHK010 Keep the shared editor-evidence-loop contract docs and the 004 feature contract note aligned.

## Evidence Safety And Edge Cases

- [ ] CHK011 Prevent a previous successful manifest from being reported as the evidence output for a build-failed run.
- [ ] CHK012 Ensure validation notes explain that no new evidence bundle was produced for the build-failed run.
- [ ] CHK013 Preserve all diagnostics when the editor reports multiple build errors for one run.
- [ ] CHK014 Preserve actionable output when the editor provides only partial location metadata.
- [ ] CHK015 Keep blocked non-build failures distinguishable from true build-failed runs.

## Deterministic Validation

- [ ] CHK016 Add or seed a deterministic broken-project case for a compile or parse failure in `examples/pong-testbed/`.
- [ ] CHK017 Add or seed a deterministic blocking resource-load failure case in `examples/pong-testbed/`.
- [ ] CHK018 Re-run the healthy autonomous evidence flow and confirm the manifest-centered success path remains unchanged.
- [ ] CHK019 Validate any updated automation result JSON against the shared schema.
- [ ] CHK020 Run the relevant existing PowerShell or regression test surfaces, or record why a given surface was not run.
- [ ] CHK021 Measure seeded build-failure request-to-result timing against the 30-second target.
- [ ] CHK022 Run seeded repair-and-retry validation cycles and record whether the build diagnostics support the expected correction rate.

## Documentation And Workflow Fit

- [ ] CHK023 Update implementation-facing docs so agents know to read the final run result first for build-failed runs.
- [ ] CHK024 Confirm the feature does not introduce a separate diagnostics transport outside the existing plugin-owned broker artifacts.
- [ ] CHK025 Confirm the plugin does not trigger automatic retries and leaves retry decisions to the agent.
- [ ] CHK026 Document any newly needed editor hooks or signals with plugin-first justification before considering broader escalation.

## Notes

- Check items off as completed: `[x]`
- Add findings inline when a check uncovers a contract gap or regression.
- Use this checklist alongside [plan.md](../plan.md), [data-model.md](../data-model.md), and [quickstart.md](../quickstart.md).