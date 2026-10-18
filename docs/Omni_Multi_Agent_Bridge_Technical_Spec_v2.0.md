# Omni Multi-Agent Bridge — Technical Specification v2.0

**Status:** Proposed architecture / not yet implemented  
**Part of:** OmniMemo v2.0 · Swift 6 + Vapor 4 + React/TypeScript  
**Date:** 19 October 2026

## 1. Product definition and ownership boundaries

Omni Multi-Agent Bridge (OMAB) is the cross-client **connectivity, message-delivery and session-lifecycle layer**, not a new model, not a replacement for native provider runtimes and not a second task scheduler.

- **Omni Agent**: choose agent/role, task priority, workflow, delegation and token budget.
- **Omni Multi-Agent Bridge**: find supported sessions and capabilities, deliver task capsules, relay supported events/results, track acknowledgments and show honest presence.
- **OmniMemo / Memory Guardian / OmniBias Guard**: validate, store and retrieve evidence, decisions and checkpoints.
- **Mission Control**: React office UI rendering observable events from Vapor; it cannot infer unseen IDE activity.
- **Omni REA / Omni Reach**: optional skills/integrations that produce evidence, never privileged message transports.

No agent owns another agent's private conversation. Cross-agent messages use explicit OmniMemo-owned schemas and references, not copied internal session databases.

## 2. Primary user story

User opens Codex in VS Code and Claude Code in a separate terminal, while OpenCode may be running in a third window. Codex proposes a bounded review task; Omni Agent creates a Task Capsule and asks OMAB to route it. The bridge first checks allowed project scope, provider capability and user approval; it either dispatches to an authorized managed worker or places the capsule in a durable inbox for a participating agent to claim. Claude sends a verifiable report and task completion acknowledgment. Codex pulls only the short result and evidence refs. React office shows honest session/activity data via Vapor WebSocket.

## 3. Scope: supported transport classes

1. **MCP stdio — common tool surface:** stable agent-visible `bridge_status`, `bridge_inbox`, `bridge_handoff`, `bridge_ack` and `bridge_result` (optional tools may be hidden until requested). MCP does NOT automatically grant cross-client session control or push messages into another model.
2. **Native hooks / plugins — lifecycle observation:** Claude Code `SessionStart`, `UserPromptSubmit`, `Stop`; Gemini CLI `SessionStart`, `BeforeAgent`, `AfterAgent`; OpenCode local plugin event handlers. All subject to installed-version probes, compatibility tests and consent.
3. **Managed runtime adapters:** Codex app-server or SDK for threads and turns **started by OmniMemo**; other providers only where documented programmatic APIs exist. Do not attach to third-party-owned sessions or inject unsolicited prompts.
4. **Vapor local API + WebSocket:** agent adapters send authorized updates; React consumes task/presence events. HTTP is bound to 127.0.0.1 by default; all endpoints require scoped authentication.
5. **Manual CLI fallback:** `om bridge inbox`, `om bridge send`, `om bridge claim`; when a host does not expose a compatible programmatic interface, queue work for manual/agent-initiated handling.

Do not require a standalone Node.js server, AMQP/RabbitMQ/Kafka, reverse proxy, second scheduler or Redis Streams for the MVP. React's Vite server is dev-only; Vapor serves the production frontend.

## 4. Supported client capability matrix (must be probed at runtime)

| Host | Lifecycle observation | Automatic context | Dispatch to managed worker | Unsupported behavior |
|---|---|---|---|---|
| Codex | MCP first-use; app-server events for OmniMemo-owned threads | Pull via MCP/tool; optional verified extension behavior | app-server/SDK or bounded `codex exec`, if approved | Arbitrarily controlling an existing user's VS Code session |
| Claude Code | SessionStart, UserPromptSubmit, Stop hooks | Supported hook context or MCP pull | Documented CLI/SDK when verified; otherwise queue/pull | Silently hijacking private desktop/cloud sessions |
| Gemini CLI | SessionStart, BeforeAgent, AfterAgent hooks | Hook context or MCP pull | Approved CLI/SDK mode if supported; otherwise queue | Assuming an IDE window provides the same CLI hooks |
| OpenCode | Plugin session.created/status/idle events | Plugin-supported integration or MCP pull | Approved SDK/server path when verified; otherwise queue | Assuming all OpenCode clients expose identical SDK control |
| Other MCP host | MCP tool calls | MCP-based on-demand context | Queue unless verified | Automatic prompt injection without supported hook |

Runtime `AgentCapability` flags must be distinct: `can_observe`, `can_receive_inbox`, `can_inject_context`, `can_launch_worker`, `can_stream_progress`, `can_cancel`, `can_write_files`, `can_use_git`. Unknown is NOT true. Record verified host version and last probe.

## 5. Data contract

### 5.1 Task Capsule (existing Omni Agent contract, extended)

```json
{
  "schema": "omnimemo.task_capsule.v2",
  "task_id": "task-uuid",
  "workspace_id": "workspace-id",
  "project_id": "project-id",
  "branch": "feature/example",
  "owner_session": "codex-session-id",
  "assigned_role": "reviewer",
  "requested_capability": "code_review",
  "goal": "Check changed Swift HTTP API for regressions",
  "allowed_paths": ["Sources/API/"],
  "input_refs": ["memory:123", "gitdiff:456"],
  "acceptance_criteria": ["cite affected line", "identify reproduction or test"],
  "max_context_tokens": 450,
  "read_only": true,
  "requires_approval": false,
  "idempotency_key": "task-uuid:v1"
}
```

Keep secret material and full dialogue transcripts out of capsules. Disallow arbitrary shell command strings in message payloads; approved adapters derive allowed actions from typed task kind and policy.

### 5.2 Event Envelope

```json
{
  "schema": "omnimemo.bridge_event.v1",
  "event_id": "uuid",
  "event_type": "task.claimed",
  "task_id": "task-uuid",
  "session_id": "claude-session-id",
  "agent_type": "claude-code",
  "workspace_id": "workspace-id",
  "seq": 19,
  "occurred_at": "2026-10-19T00:00:00Z",
  "payload": {"status": "running"},
  "trace_id": "trace-uuid"
}
```

Events may arrive more than once or out of order. Consumers deduplicate by `event_id` and resolve canonical state using MongoDB task revisions; do not promise exactly-once delivery.

### 5.3 Task lifecycle

`created -> pending_approval | queued -> claimed -> running -> review -> completed`  
Alternative terminal states: `failed`, `cancelled`, `expired`; an agent disconnect may cause `unconfirmed` until lease expiration. `completed` requires an actual result and relevant evidence, not merely that an agent went idle.

## 6. MongoDB and Redis responsibilities

**MongoDB is source of truth:** collections `bridge_sessions`, `bridge_tasks`, `bridge_events` (bounded retention), `bridge_approvals`, existing memories and evidence. Use atomic `findOneAndUpdate` plus revision/lease checks for task claims. Event log/task state survive Redis loss. Require no complex multi-document transactions in MVP; if atomic updates across multiple collections become essential, use replica set transactions and benchmark them.

**Redis is acceleration, not authority:** short-lived `presence:{session}`, recent context cache, Pub/Sub event notification for active WebSockets. A subscriber must reconcile missed events using MongoDB cursor/revision upon reconnect. Redis failure -> memory/task operations remain functional via MongoDB and status falls back to poll. Do not use Pub/Sub as guaranteed delivery.

**Local portable disk:** non-secret logs/evidence artifacts in configurable `local_data_dir`, content hashes/references in MongoDB. Use retention caps; don't duplicate full repo or transcript in memory. Preserve external-SSD unavailable behavior (never secretly create new storage elsewhere).

## 7. Runtime and activation

**One on-demand Swift/Vapor coordinator** handles HTTP, WebSockets, event normalization and bridge inbox. Host hooks or the first MCP tool interaction can boot/reuse it using an atomic lock + process health check. React office does not need to be opened. `om bridge` can explicitly bring it up. If user enables `always_on`, manage one service through OS facilities; otherwise idle shutdown only when no active client task/approval and no pending operation requires the runtime. Avoid polling every IDE/process in the system.

A first-prompt hook injects at most one small, scoped memory/context capsule per session/prompt where supported. Session startup context and first-prompt injection must be idempotent. If a hook times out, continue agent work with clear degraded health rather than repeatedly blocking user prompts.

## 8. Security model

1. Local-only binding by default; scoped bearer token or OS-local credential in secure storage, WebSocket origin validation. Never publicly expose the service by default.
2. Each adapter has a distinct trusted identity; authenticated account **does not** grant unrestricted workspace scope. Project ACLs gate inbox, memory and artifacts.
3. External retrieval and agent outputs are untrusted data; never treat their embedded instructions as permissions or automatic commands.
4. Git: `YanIanZ` is allowed GitHub destination owner; newly agent-authored commit author/committer must use the GitHub-verified email chosen by the human. Push only after a fresh explicit approval, verifying actual authenticated credential and effective remote; no approval delegation to agents.
5. Read-only review default. Editing requires project/path grants; no concurrent edits in the same worktree. Approved isolated worktrees if needed. No unattended chmod/chown, remote changes, git hooks modifications, or dependency installation.
6. REA and Agent Reach permissions remain separate; research access or read-only software analysis does not imply code write or network posting.
7. Audit log records agent, action, approval decision and artifact hashes, not full secret-bearing content.

## 9. Core MCP interface (v2 first slice)

| Tool | Main input | Output |
|---|---|---|
| `bridge_status` | workspace id | connected/unknown sessions + validated capabilities |
| `bridge_inbox` | workspace and max_items | pending authorized tasks with brief capsule refs |
| `bridge_handoff` | destination capability, capsule | task id, queued/approval state |
| `bridge_ack` | task id, observed revision | claimed or conflict; claim lease |
| `bridge_result` | task id, result refs, tests | durable result + lifecycle update |

Add streaming and cancellation tools only after basic handoff works. Keep tool schemas short and only expose bridge tools when the bridge skill is active.

## 10. REST/WebSocket extension (Vapor)

- `GET /api/v1/bridge/agents` — observed roster/capability report.
- `GET /api/v1/bridge/tasks` — paged task board.
- `POST /api/v1/bridge/tasks` — create scoped handoff after authentication/permission check.
- `POST /api/v1/bridge/tasks/:id/approve` — human approval (CSRF and session authorization required).
- `GET /api/v1/bridge/events?after=cursor` — recover changes missed during disconnect.
- `WS /ws/v1/live` — authenticated presence/task updates with sequence numbers.

No passwords/tokens in URLs or WebSocket event payloads. Rate limits and request limits apply. Office avatars show `online` only after a valid heartbeat and `working` only after observed task execution; use `unknown` after heartbeat expiry.

## 11. CLI shape (planned, not implemented)

```text
om bridge status
om bridge doctor
om bridge agents
om bridge inbox
om bridge send --to claude-code --task task.json
om bridge claim <task-id>
om bridge result <task-id> --file review.md
om office
```

`om` stays the only user-facing executable. `om bridge` is a subcommand, not a separate service/binary. `om office` opens React UI served by the existing Vapor coordinator.

## 12. Token, performance and anti-overengineering rules

- One default worker; max two only for independently useful tasks that justify extra tokens.
- Capsule default 450 tokens, hard cap configurable (max 1200 recommended). Result summary default <=600 tokens plus evidence refs.
- No full transcripts, entire codebase copy or repeated retrieval for every heartbeat/event.
- Prefer one task handoff and an explicit result rather than agent-to-agent chat loops.
- Coalesce UI status updates and batch event delivery; avoid sending one WebSocket event for each generated token.
- Measure cost at all participating providers when usage is available; unknown must remain unknown.
- Benchmark additional latency and token cost versus manual/one-agent baseline. If delegation costs more with no quality benefit, keep one agent.
- Cache max 32 MiB by default (Reach 8 MiB subquota), while persistent Mongo data and artifact retention are separate.

## 13. MVP implementation order

**M0:** small Swift library/types for session/capability/event/task message formats; unit tests.  
**M1:** two client adapters (Codex managed worker / Claude hook or inbox pull), durable Mongo task queue, `om bridge` commands; one full handoff.  
**M2:** Vapor WebSocket event fanout and React task/office roster; Redis presence only when available.  
**M3:** Gemini/OpenCode adapters, capability probes, approved parallel worker execution and reconnect/recovery tests.  

Don't add new shared infrastructure or architectural indirection without benchmark-supported need.

## 14. Acceptance tests

| ID | Scenario | Expected outcome |
|---|---|---|
| MB-01 | Codex tasks Claude with same workspace | One durable capsule delivered/claimed |
| MB-02 | Claude is not running | Task queued, not falsely marked working |
| MB-03 | Claimed by two workers simultaneously | One successful atomic claim |
| MB-04 | Redis stops/restarts mid-task | Mongo task/result survives; UI later reconciles |
| MB-05 | Vapor restarts after event was acknowledged | Missed event replay via cursor; no phantom completion |
| MB-06 | Hook unavailable/version mismatch | CLI/MCP inbox fallback with diagnostic |
| MB-07 | First prompt with both startup and per-prompt hooks | No duplicate context/inbox injection |
| MB-08 | Review source contains malicious instructions | Instructions treated as untrusted evidence, not executed |
| MB-09 | Wrong project or worktree | Denied with scoped error; no data leak |
| MB-10 | Two writers target the same file | Serialized or separate approved worktrees |
| MB-11 | Unauthorized commit/push | Rejected regardless of request from another agent |
| MB-12 | One client goes silent | Presence becomes unknown, not permanently online |
| MB-13 | React UI closed | Bridge and MCP memory work without frontend |
| MB-14 | Missing MongoDB | Explicit degraded mode per configured profile; no misleading success |
| MB-15 | No real delegation advantage | One-agent mode selected; measured token budget honored |
| MB-16 | Local SSD unavailable | No shadow DB/cache in wrong directory; state preserved on recovery |
| MB-17 | Provider event type unsupported | Normalize to unknown; no fabricated working metrics |
| MB-18 | User approves one specific push | Approval does not apply to future push or another repo |

## 15. Observability

Only emit sparse status events: `session.registered`, `session.heartbeat`, `session.disconnected`, `task.created`, `task.approval_required`, `task.claimed`, `task.progress`, `task.completed`, `task.failed`, `task.cancelled`, `bridge.degraded`. Use timestamps and monotonically increasing revisions for ordering. An event isn't proof of test success; test evidence must be attached separately.

## 16. References (checked 2026-10-19)

- Codex app-server/SDK: https://developers.openai.com/blog/codex-as-a-platform
- Claude Code hooks: https://code.claude.com/docs/en/hooks
- Gemini CLI hooks: https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/index.md
- OpenCode plugins: https://docs.opencode.ai/docs/plugins/

**Not implemented**. All commands and contracts above are proposed. Validate host/runtime versions and security integrations before claiming support.
