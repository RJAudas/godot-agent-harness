# Godot Agent Harness

Godot Agent Harness is a plugin-first project for improving **agent-driven game development** in Godot.

The core goal is to give agents **structured runtime feedback** instead of relying on a human to repeatedly run the game and describe what went wrong in natural language.

## Project goal

Build a Godot-compatible harness that helps agents:

- run deterministic gameplay scenarios
- inspect the runtime scene tree / node graph
- capture machine-readable frame traces
- collect structured gameplay events and logs
- evaluate invariants automatically
- diagnose runtime failures from evidence

This project is intentionally starting as a **plugin/addon**, not an engine fork.

## Why this exists

The current feedback loop for agent-built games is weak:

1. Agent changes code.
2. Human runs the game.
3. Human explains behavior.
4. Agent guesses.

That breaks down on bugs like:

- incorrect Pong bounce physics
- objects not instancing
- collisions behaving incorrectly
- infinite gameplay loops

The harness is meant to become the missing observability layer.

## Approach

Start with the least invasive path:

1. **Editor plugin / addon**
2. **Runtime addon + autoload singleton**
3. **Debugger integration**
4. **GDExtension if needed**
5. **Engine fork only as a last resort**

## Repository layout

```text
addons/
  agent_runtime_harness/   # plugin/addon implementation
docs/
  AGENT_RUNTIME_HARNESS.md # requirements and architecture
  GODOT_PLUGIN_REFERENCES.md
examples/
  pong-testbed/            # minimal validation project
scenarios/                 # deterministic scenario definitions
tools/                     # helper scripts and runner utilities
```

## Documentation

- Requirements and implementation direction: `docs/AGENT_RUNTIME_HARNESS.md`
- Curated Godot extension references: `docs/GODOT_PLUGIN_REFERENCES.md`

## Reference strategy

This repository should **not vendor the full Godot documentation**.

Instead, it should keep:

- concise local design notes
- curated links to official docs
- implementation-specific notes learned while building the harness

That keeps the repo lightweight while still giving agents enough context to work effectively.
