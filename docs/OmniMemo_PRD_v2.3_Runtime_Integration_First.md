# OmniMemo PRD v2.3 — Runtime Integration First

**Status:** Proposed / implementation specification, not deployed  
**Updated:** 2026-10-19  
**Priority:** P0 runtime observation and integration.  
**Supersedes:** v2.2 priorities for new work. Preserves all existing OmniMemo features and policies.

## Product decision

Stop new purely visual Office improvements until the dashboard reflects **real runtime activity**. Never synthesize AI activity from an avatar animation. Existing React pixel-art office and layouts remain; data moves from demo/mock task updates to normalized adapter events.

Primary stack: **Swift 6**, **Vapor 4** (HTTP/WebSocket), **React + TypeScript**, **MongoDB** durable state, **Redis** ephemeral event/presence cache, **Swift ArgumentParser** `om`. No new primary database, message broker, LLM, or web framework.

## P0 user story

Given a user with Claude Code in terminal, OpenCode in its own client, Codex managed by Omniverse, and Gemini CLI:
- When a supported session starts, it appears once in Agent Office.
- When the agent receives a prompt, its status and sanitized task title update.
- When it uses a tool, the state changes to Working without disclosing source code, arguments, or secrets.
- When a tool/turn completes, its event history reflects the actual result, including failure.
- When a model change is observable, the agent label updates from verified metadata.
- When activity becomes unobservable, the UI says **Last seen / Signal stale** rather than fabricating progress.
- When milestones are independently verified, the progress bar shows completed/total; otherwise an indeterminate bar is used.

## Scope and implementation order

| Gate | Priority | Work | Source of truth | Definition of done |
|---|---|---|---|---|
| P0.0 | Contract | Shared event schema, identity mapping, observed/inferred/reported confidence | Source adapter events | Contract tests and sample fixtures |
| P0.1 | OpenCode | TypeScript plugin events for session, messages, tools, errors, idle | OpenCode plugin SDK | New session + tool activity shown within 2s local |
| P0.2 | Claude Code | Hook adapter: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SessionEnd; model switch when supported | Claude lifecycle hooks | Live session and end-of-turn + model updates |
| P0.3 | Gemini CLI | JSON hooks: SessionStart, BeforeAgent, BeforeTool, AfterTool, AfterAgent, SessionEnd | Gemini hooks | Live user turn and tool activity |
| P0.4 | Codex | Manage Codex via documented app-server; map thread/turn/item notifications | Codex app-server for sessions launched/attached by supported protocol | Managed Codex session live on board |
| P0.5 | Swift Bridge | POST events -> validate -> normalize -> dedup -> persist -> broadcast | Vapor, MongoDB, Redis optional | No lost task data after Redis restart |
| P0.6 | React Office | Wire cards, avatar location, events and progress to normalized event feed | Snapshot + WebSocket | No demo status unless Demo Mode explicitly on |

**Not in P0:** motion/animation polish, model inference-based ETA, remote desktop control, scraping private IDE session files, arbitrary process scanning, new storage engine, native Claude binary patching, cloud sync, automatic provider login, auto-push to GitHub.

## Activation and support boundaries

1. `om service install` (with approval) optionally registers a user-level macOS launchd agent for the local Vapor service. Starting an IDE window alone does **not** guarantee a session event.
2. `om integrations install` edits supported per-client config with backup and explicit user approval. Idempotent; never overwrite other hooks/plugins.
3. SessionStart / plugin initialization / app-server initialization registers a session, with `observability: passive|managed`.
4. First user prompt triggers lazy OmniMemo recall at most once per context version, with user-configured token cap. Inject only if the host supports a documented context hook. Status observation must still work if recall fails.
5. MCP connection can register a host only if it identifies a session; connection alone is not proof of agent work.
6. For unknown/unsupported IDE lifecycle features, show `Manual handoff available`, not fake direct control.

## Identity schema

Internal primary key: `runtime_session_id` (UUID), never client/model display name. `external_session_id` is scoped to `provider + workspace_id`. Provider `client` = `claude`, `codex`, `opencode`, `gemini`; `model_id` must come from adapter metadata or be `null`.

Display: `{client}-{normalized_model_id}` e.g. `opencode-kimi-k2.7-code` **only when actually reported**. If unavailable, `opencode-model-unavailable`. User aliases are separate `display_alias`; if multiple equal names display short local session suffix, e.g. `opencode-kimi-k2.7-code · a9c1`.

Never treat model name as authorization. Changes of model do not create a new agent identity, only update label/history.

## Runtime event contract

Minimum schema: `event_id` (UUID), `schema_version`, `source`, `provider`, `external_session_id`, `workspace_id`, `event_type`, `occurred_at`, `received_at`, `sequence?`, `model_id?`, `task_id?`, `milestone_id?`, `status?`, `source_confidence` (`observed|reported|inferred`), and carefully filtered `metadata`.

Allowed event types:
`session.started`, `session.resumed`, `session.ended`, `model.changed`, `prompt.received`, `tool.started`, `tool.succeeded`, `tool.failed`, `turn.completed`, `turn.failed`, `task.assigned`, `task.blocked`, `milestone.verified`, `approval.requested`, `heartbeat`.

Reject invalid combinations; idempotency key = `source + external_session_id + event_id`, with bounded dedup retention. Handle reorder and repeated events using source ordering and timestamps; persist arrival order separately. Never consume an arbitrary command from the event payload.

## Status semantics — no fake agent presence

`Working`: positive event showing turn or tool in progress.  
`Reviewing`: active task assigned review role, plus actual activity evidence.  
`Waiting`: explicit idle/turn completed event with session still known.  
`Blocked`: actual approval/dependency/denial event.  
`Done`: verified task completion, not merely end of turn.  
`Stale`: last observed signal aged past threshold, no corroborating live evidence.  
`Offline`: observed process or session termination, not just lack of hooks.  
`Unknown`: cannot reliably determine from current host capability.

For **managed** sessions with an owner process, send heartbeat every 10–15 s; mark `Stale` after a configurable 45s; `Offline` after verified exit/disconnect and grace period. For **passive** hook-only sessions do not invent a periodic heartbeat; show `Last seen` and stale if signal stops, even when process might be running.

## Progress measurement

Task progress = `(sum weights of verified, completed milestones) / (sum weights of all defined milestones)`. Default equal weights. Never change milestone denominator retroactively without a versioned replan. If milestones undefined or unverified, show indeterminate activity bar with **no numeric %**. Tool count, generated tokens, elapsed time, or generic LLM verbal estimates are not valid progress. Allow the user to correct milestone state; preserve audit trail.

## Persistence and broadcast

- **MongoDB:** sessions, tasks, milestones, event snapshots, approvals, checkpoint and memory evidence. A durable outbox is optional only if multi-instance delivery tests require it.
- **Redis:** short TTL presence state, Pub/Sub for UI fanout in multi-Vapor deployments. Redis unavailable => degraded mode; durable tasks remain in MongoDB. Never rely on Redis Pub/Sub as reliable delivery.
- **Vapor:** `POST /api/runtime/events`, `GET /api/runtime/sessions`, `GET /api/runtime/tasks`, `GET /api/runtime/health`, `GET /ws/office` (WebSocket). Socket clients subscribe to workspace-scoped events. On reconnect fetch snapshot + cursor and reconcile duplicate/out-of-order messages.
- **React:** existing Agent Office rooms, cards, latest events, connection health, model labels, milestone progress; show badges only when warranted. Keep demo mode explicit and visibly separate.

## Privacy & permissions

- Default event collection is minimal and **does not store full prompts, transcript, source text, tool arguments, secrets, cookies, or API keys**. Only sanitized short task titles if user authorizes. Workspace-level on/off switches.
- Bind Vapor HTTP to `127.0.0.1` by default, use per-client token/IPC if applicable; restrict Origin and CORS; authorization per workspace/session; reject untrusted process registration.
- Opaque IDs over absolute paths in broadcasts; never share one project's metadata with another without permission.
- Remote access OFF by default. No external provider calls caused merely by presence updates.
- Keep anti-overengineering, OmniBias Guard, no automatic pushes. Git author/committer and authenticated push account must match authorized `YanIanZ` account and verified email; require user approval for push. This is an implementation policy, not proof from git config alone.

## Runtime mapping notes

**Claude Code:** Hook lifecycle supports `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionEnd`, `PostModelSwitch` and optionally `TaskCreated`/`TaskCompleted`. Hooks may work across Claude environments according to official host support. Hook payloads carry session ID. Keep hook command silent on stdout unless intentionally returning supported JSON; timeouts and errors must not block the user prompt by default.

**OpenCode:** Plugin system surfaces `session.created`, `session.status`, `session.idle`, `session.error`, `message.updated`, `tool.execute.before/after`; use `event` and tool hooks through official SDK. Do not assume event payload schema stable across OpenCode versions without fixture-based mapping.

**Gemini CLI:** `SessionStart`, `BeforeAgent`, `BeforeTool`, `AfterTool`, `AfterAgent`, `SessionEnd`; hooks communicate JSON through stdin/out and require strict stdout discipline. Inject context only with documented fields; suppress logs from stdout.

**Codex:** For Omniverse-managed processes, connect app-server to threads and turns; derive `turn` and `item` events, model/catalog metadata; accept user approvals. Sessions opened separately within VS Code are not universally controllable via app-server. Show limited/manual capability when no official bridge exists.

## Reliability and performance targets (design objectives, not verified results)

- Locally delivered events visible in Office p95 <2 seconds after ingestion in development benchmark.
- Hook fast-path p95 <150ms local, with low overhead and hard timeout. If exceeded, asynchronously spool or skip non-critical telemetry, never hold up a prompt indefinitely.
- Zero invented model labels or percentages in test suite.
- Redis restart does not erase MongoDB-backed task state.
- Event duplication/reorder cannot drive progress backwards silently or duplicate sessions.
- Multiple IDEs with same provider/model appear as distinct sessions.
- React reconnect reconciles snapshot/cursor after temporary offline connection.

## Milestones and definition of done

**Milestone A — real OpenCode:** Start OpenCode and one prompt; see real agent in Office, tool events, `Waiting` after idle. No simulation.

**Milestone B — real Claude:** SessionStart / tool events / Stop + model change reflected in UI. Test Claude Code Mod is an enhancement, not a requirement for telemetry.

**Milestone C — real Gemini:** Equivalent start/turn/tool/exit semantics with correct hook JSON.

**Milestone D — managed Codex:** Start via documented app-server and see actual thread/turn/item stream. Mark independently-launched VS Code sessions as unsupported/manual when applicable.

**Milestone E — resilient Swift/React system:** Kill Redis, restart Vapor, disconnect browser, end agent abruptly, change model, duplicate event; verify status and data recovery.

**Milestone F — privacy and policy:** Show logs do not contain raw prompts/secrets; perform authorization rejection tests; demonstrate GitHub identity lock and push approval.

## Next concrete work in repository

1. Inspect existing runtime, Vapor routes, MongoDB models, Redis code and React state; identify which statuses currently come from CLI simulation.
2. Add event types and validators **without rewriting the current app**.
3. Implement a Swift event-ingest path and snapshot endpoint.
4. Integrate **OpenCode first**, then Claude hooks; test end-to-end with real local runs.
5. Add Gemini hooks and managed Codex app-server.
6. Wire UI cards and pixel-office avatar status to normalized streams; preserve existing layout.
7. Add test fixtures and `om runtime doctor` diagnostics. Avoid speculative orchestration features until real events work.

## References (upstream docs consulted 2026-10-19)

- https://code.claude.com/docs/en/hooks
- https://opencode.ai/docs/plugins/
- https://geminicli.com/docs/hooks/reference/
- https://developers.openai.com/codex/app-server
- https://developers.openai.com/blog/codex-as-a-platform

This document is a **specification**. No claim of implementation, real IDE integration, installation or GitHub push is made.
