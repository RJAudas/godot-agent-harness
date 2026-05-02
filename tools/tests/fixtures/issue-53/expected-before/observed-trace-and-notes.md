# Issue #53 — pre-fix evidence

Captured 2026-05-02T22:30 against `D:/gameDev/pong` using harness commit `1d828a2`.

The fixture [non-contiguous-frames-repro-pong.json](../non-contiguous-frames-repro-pong.json)
asks for `behaviorWatchRequest.frameCount: 60` watching
`/root/Main/Ball.linear_velocity`. The orchestrator returns `status: success`
with the `target node not found or never sampled` warning (that's the
pre-existing orchestrator-vs-manifest mismatch from #46/#47, ignore it —
the manifest's outcomes block reports the truth).

**Observed:** 56 rows for the 60 requested frames. Both symptoms from
the issue are present in this single run.

## Gap analysis (frame deltas between consecutive rows)

| delta | count |
|---|---|
| 0 | 1   ← two physics ticks in the same render frame; the second was sampled but reported under a duplicate frame label |
| 1 | 51  ← contiguous (the happy case) |
| 2 | 3   ← render-frame counter jumped 2 between physics ticks; one physics tick had no sample |

Specific anomalies:

```
row 1 frame=2 -> row 2 frame=4 (delta=2)
row 7 frame=9 -> row 8 frame=11 (delta=2)
row 14 frame=17 -> row 15 frame=19 (delta=2)
row 36 frame=40 -> row 37 frame=40 (delta=0)
```

The 4 anomalies × ~1 missing/duplicate row each ≈ the 4-row shortfall
(56 captured vs 60 requested).

## Why this happens

The sampler is hooked into `_physics_process` (driver fires every physics
tick at 60 Hz) but reports `Engine.get_process_frames()` — the **render**
frame counter — as the `frame` value at
[scenegraph_runtime.gd:271](../../../../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd#L271).

When the editor's render rate diverges from physics (which it does even on
an idle machine — vsync, browser, IME, etc.), the render counter doesn't
tick 1:1 with the physics counter:

- **delta=2 rows**: a physics tick fired between two render frames that
  didn't both pass `_physics_process` (or the render counter advanced 2
  while only 1 physics tick passed) — the trace looks like a frame was
  silently dropped.
- **delta=0 rows**: two physics ticks both fell within one render frame's
  process-counter value; both were captured (rows are appended) but
  `_sampled_frames[str(frame)] = true` deduped them in the per-frame
  count.

Same code, same physics — the result depends on host load. That's the
"silently denied that working code was working" failure mode the issue
calls out.
