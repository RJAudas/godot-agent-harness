Set-StrictMode -Version Latest

function Get-EvidenceArtifactDefinitions {
    return @(
        @{ kind = 'trace'; file = 'trace.jsonl'; mediaType = 'application/jsonl'; description = 'Per-frame trace data for the runtime sample.' },
        @{ kind = 'events'; file = 'events.json'; mediaType = 'application/json'; description = 'Structured runtime events for the sample run.' },
        @{ kind = 'scene_snapshot'; file = 'scene-snapshot.json'; mediaType = 'application/json'; description = 'Scene snapshot captured around the failure window.' },
        @{ kind = 'scenegraph-snapshot'; file = 'scenegraph-snapshot.json'; mediaType = 'application/json'; description = 'Bounded runtime scenegraph snapshot captured during the play session.' },
        @{ kind = 'scenegraph-diagnostics'; file = 'scenegraph-diagnostics.json'; mediaType = 'application/json'; description = 'Structured scenegraph diagnostics produced from scenario expectations.' },
        @{ kind = 'scenegraph-summary'; file = 'scenegraph-summary.json'; mediaType = 'application/json'; description = 'Agent-readable scenegraph inspection summary for the play session.' },
        @{ kind = 'stdout_summary'; file = 'summary.json'; mediaType = 'application/json'; description = 'Normalized summary for the sample run.' },
        @{ kind = 'invariant_report'; file = 'invariants.json'; mediaType = 'application/json'; description = 'Invariant outcomes for the sample run.' },
        @{ kind = 'input-dispatch-outcomes'; file = 'input-dispatch-outcomes.jsonl'; mediaType = 'application/jsonl'; description = 'Per-event runtime input-dispatch outcomes for the input-dispatch feature.' }
    )
}

function Get-EvidenceArtifactKinds {
    return @(Get-EvidenceArtifactDefinitions | ForEach-Object { $_.kind })
}