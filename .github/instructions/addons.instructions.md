---
applyTo: "addons/agent_runtime_harness/**"
---

# Addon Instructions

- Keep changes plugin-first and compatible with normal Godot addon patterns.
- For GDScript addon code, keep `const` initializers to literal constant expressions (`[]`, `{}`, scalars) instead of constructors such as `PackedStringArray(...)`, and prefer explicit `RegEx`/`RegExMatch` typing when APIs like `search()` do not infer cleanly.
- Prefer structured runtime outputs that an agent can consume directly over editor-only UI state.
- Preserve deterministic scenario and evidence expectations when introducing runtime-facing behavior.
- Do not propose engine-fork changes from addon files unless the task includes evidence that addon, debugger, and GDExtension options are insufficient.
- When a tooling task touches addon files, document the runtime evidence it should emit or consume.
