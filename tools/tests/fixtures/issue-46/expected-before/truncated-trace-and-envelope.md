# Issue #46 — pre-fix evidence

Captured 2026-05-02T21:28 against `D:/gameDev/pong` using harness commit `26253bc`.

The fixture [truncation-repro-pong.json](../truncation-repro-pong.json) asks for
`behaviorWatchRequest.frameCount: 30` with `stopPolicy.stopAfterValidation: true`.
The orchestrator returns `status: success`, but the trace contains only 2 rows —
the playtest was killed at validation (~frame 5) before the watch's 30-frame
window could populate.

## Envelope (success)

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "D:/gameDev/pong/evidence/automation/runbook-behavior-watch-20260502T212837Z-a25d10/evidence-manifest.json",
  "diagnostics": []
}
```

## Trace (2 rows of 30 requested = 7% capture)

```jsonl
{"frame":1,"linear_velocity":[389.147125244141,-65.9605102539063],"nodePath":"/root/Main/Ball","timestampMs":1}
{"frame":2,"linear_velocity":[388.49853515625,-65.8505783081055],"nodePath":"/root/Main/Ball","timestampMs":20}
```

The harness silently agreed that a request for 30 frames was satisfied by 2.
This is the verification gap the fix closes.
