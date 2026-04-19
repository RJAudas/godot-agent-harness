# Input-Dispatch Request Fixtures

This directory holds deterministic per-story fixtures for the Runtime Input
Dispatch feature (`specs/006-input-dispatch/`).

Files follow this naming convention:

- `valid-<scenario>.json` — request bodies expected to normalize and dispatch.
- `invalid-<reason>.json` — request bodies expected to reject with the matching
  rejection reason code (for example `invalid-script-too-long.json`).

The canonical reproduction for issue #12 (Pong title-screen numpad-Enter
`_unhandled_input` crash) lives in `valid-numpad-enter.json`. See
`specs/006-input-dispatch/quickstart.md` for the exact steps.
