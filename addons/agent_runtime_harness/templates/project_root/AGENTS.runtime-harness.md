## Runtime Harness Workflow
1. Read `.github/copilot-instructions.md` for repo-wide guidance and the runtime evidence workflow.
2. Inspect `project.godot` to confirm the harness plugin and autoload wiring before assuming runtime capture is available.
3. When runtime evidence exists, read `evidence/scenegraph/latest/evidence-manifest.json` before opening raw artifacts.
4. Only inspect raw scenegraph artifacts that the manifest references.

## Runtime Verification Rules
- Use **ordinary tests** for unit, contract, framework, and other non-runtime checks.
- Use **Scenegraph Harness runtime verification** for requests such as "verify at runtime," "test the running code," "make sure the node appears in game," "confirm the node exists while playing," or other runtime-visible outcomes.
- Use **combined validation** when a change affects runtime-visible behavior and there is already a direct deterministic test surface. Run the existing tests and the harness flow together, but do not invent new ordinary tests only to satisfy the combined rule.
- If the user already provides `evidence/scenegraph/latest/evidence-manifest.json` and only wants diagnosis, stay in the evidence-triage workflow instead of launching a fresh run.
- Prefer runtime evidence over human retellings when verifying whether a gameplay change worked.
- Keep gameplay changes separate from harness changes when possible. Modify `addons/agent_runtime_harness/` only when the task actually concerns capture, transport, or evidence persistence.
- Treat the Scenegraph Harness dock as the operator control surface and the persisted evidence bundle as the agent handoff surface.
- If runtime verification fails, distinguish between a gameplay failure and a harness wiring failure such as a missing autoload or no persisted bundle.
- For autonomous editor evidence runs, prefer the file-broker path under `harness/automation/requests/` and `harness/automation/results/` before considering fallback surfaces.
- Read `harness/automation/results/capability.json` or the latest final run result before opening raw evidence files.
- Treat blocked capability or run results as explicit unsupported-state signals; do not guess around them with hidden editor interaction.
