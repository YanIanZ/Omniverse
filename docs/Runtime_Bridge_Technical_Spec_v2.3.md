# OmniMemo v2.3 — Runtime Bridge Technical Contract

## Module boundary

Client adapters produce **events**, not UI state. The Swift Vapor service validates and normalizes these, persists durable transitions in MongoDB, optionally publishes ephemeral changes through Redis, and broadcasts to React via WebSocket. React **derives view state only from snapshots + events**. The Omni Agent orchestrator is separate and optional: observation of a runtime must not trigger a delegation.

```text
Claude hooks ─────┐
OpenCode plugin ──┤
Gemini hooks ─────┼─> Swift event-ingest -> schema/security -> MongoDB
Codex app-server ─┘                                         │
                                         Redis presence/pubsub (optional)
                                                            │
                                             Vapor /ws/office
                                                            │
                                                React Agent Office
```

## Capture lifecycle

**Passive adapters**: run only on supported lifecycle events. Do not fabricate heartbeat; status cannot be guaranteed between events.

**Managed adapters**: runtime launched by OmniMemo with an owned process and an official protocol. Heartbeats / process exit become stronger evidence for presence.

## REST contract (proposed)

`POST /api/runtime/events` — authenticated event ingest; success `202 {accepted:true, cursor:"..."}`; duplicates return `200 {accepted:false, duplicate:true}`.

`GET /api/runtime/sessions?workspace_id=...` — authoritative snapshot, including timestamps, source/evidence class, display labels, and current state. Only authorized workspaces.

`GET /api/runtime/tasks?workspace_id=...` — task/milestone snapshot.

`GET /api/runtime/health` — Mongo/Redis/bridge diagnostic with no credentials or sensitive paths.

`GET /ws/office?workspace_id=...` — authenticated WebSocket upgrade for `runtime.session.updated`, `runtime.task.updated`, `runtime.approval.updated`, and `runtime.health.changed`. Do not include secret tokens in query string in production; use suitable browser/session authentication and Origin enforcement.

## Minimal Swift types (illustrative contracts; not compiled)

```swift
enum AgentClient: String, Codable { case claude, codex, opencode, gemini }
enum EventType: String, Codable {
    case sessionStarted = "session.started"
    case sessionEnded = "session.ended"
    case promptReceived = "prompt.received"
    case toolStarted = "tool.started"
    case toolSucceeded = "tool.succeeded"
    case toolFailed = "tool.failed"
    case turnCompleted = "turn.completed"
    case modelChanged = "model.changed"
    case milestoneVerified = "milestone.verified"
    case heartbeat
}
```

## Recommended persistence

- Collection `runtime_sessions` unique index `(workspace_id, provider, external_session_id)`, store observed version.
- Collection `runtime_events` unique index `(workspace_id, provider, external_session_id, event_id)` and TTL retention for telemetry metadata (separate durable checkpoint/task collection).
- Collection `runtime_tasks` versioned milestones and verification evidence.
- Collection `runtime_outbox` for durable publication if multi-instance fanout is later needed; do not add this complexity until tested need.
- Redis keys for presence are short TTL, not source of truth.

## Real event to office mapping

| Input event | Agent status | Office location | Progress |
|---|---|---|---|
| session.started | Waiting (or Known) | Lounge | No percentage |
| prompt.received | Working | Workspace | unchanged |
| tool.started | Working | Workspace | unchanged |
| task review assigned + observed work | Reviewing | Review | unchanged |
| approval.requested | Blocked | Approvals | unchanged |
| turn.completed/session.idle | Waiting | Lounge | unchanged |
| milestone.verified | based on current activity | same | recompute verified ratio |
| session.ended | Offline | inactive | unchanged |
| silence past threshold | Stale/Last seen | retain last known | unchanged |

**UI nuance:** room movement is symbolic and may lag state; label it as a visualization, never claim physical process or model activity beyond event evidence.

## Client-specific adapter boundaries

- OpenCode: plugin TS (`event`, `tool.execute.before`, `tool.execute.after`), filter metadata, debounce high-volume updates. Use official `@opencode-ai/plugin` contract.
- Claude: event hooks via plugin or settings. Observe `SessionStart`, `UserPromptSubmit`, tool lifecycle, `Stop`, `SessionEnd`, and `PostModelSwitch` when supported. Do not patch Claude binary.
- Gemini: command hook JSON and strict stdout. Agent memory injection separate from telemetry.
- Codex: app-server for OmniMemo-owned session lifecycle. Do not attempt to take over unrelated VS Code Codex sessions.

## Required end-to-end tests

1. Two simultaneous OpenCode sessions with the same model -> two cards.
2. Claude startup -> prompt -> tool failure -> Stop -> correct event trail.
3. Gemini hook handler output on stdout remains valid JSON or empty as documented.
4. Codex app-server client launched -> thread/turn events visible; unmanaged VS Code Codex is marked limited.
5. No telemetry includes raw prompt, transcript, tool arguments, or known test secrets.
6. All progress numbers correspond to verified milestones.
7. Duplicate events and event reordering are handled deterministically.
8. Redis connection drops -> snapshot still works.
9. Browser disconnects and reconnects -> correct state without double-count.
10. Missing hook SessionEnd -> `Stale`, not fabricated `Offline`.
11. `om runtime doctor` lists adapter/version/effective capabilities and reasons for unavailable statuses.
12. No Git push is attempted; a push attempt without approval is denied.
