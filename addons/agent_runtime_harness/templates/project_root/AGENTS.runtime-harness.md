## Runtime Harness Workflow
1. Read `.github/copilot-instructions.md` for repo-wide guidance and the runtime evidence workflow.
2. Inspect `project.godot` to confirm the harness plugin and autoload wiring before assuming runtime capture is available.
3. When runtime evidence exists, read `evidence/scenegraph/latest/evidence-manifest.json` before opening raw artifacts.
4. Only inspect raw scenegraph artifacts that the manifest references.

## Runtime Verification Rules
- Prefer runtime evidence over human retellings when verifying whether a gameplay change worked.
- Keep gameplay changes separate from harness changes when possible. Modify `addons/agent_runtime_harness/` only when the task actually concerns capture, transport, or evidence persistence.
- Treat the Scenegraph Harness dock as the operator control surface and the persisted evidence bundle as the agent handoff surface.
- If runtime verification fails, distinguish between a gameplay failure and a harness wiring failure such as a missing autoload or no persisted bundle.