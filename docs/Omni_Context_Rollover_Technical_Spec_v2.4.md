# Omni Context Rollover — Technical Specification v2.4

**Project:** OmniMemo · Swift / Vapor / React / MongoDB / optional Redis  
**Status:** Proposed — not implemented or installed  
**Repository audited:** https://github.com/YanIanZ/OmniMemo (main, 2026-10-19)

## Product goal

Replace repeated lossy conversation compaction with **fresh-session rollover** whenever a supported agent reports that the *active model context* is approaching capacity. Create a bounded, evidence-backed checkpoint; verify it; start a genuinely clean session; deliver capsule once; require acknowledgement; transfer task ownership; retire the parent. Maintain a complete session lineage without carrying raw chat histories into the next session.

The feature is called **Omni Context Rollover**, coordinated by **Omni Multi-Agent Bridge**. The default mode is `suggest` (manual continuation); `auto_managed` requires explicit opt-in and a verified runtime API to create a new session. No random process launch or private IDE scraping.

## Definitions

- **Context occupancy**: actual reported tokens occupying the active context window, NOT lifetime token totals, API charges, rate limits or token budgets.
- **Authoritative usage**: per-session reported ratio or compatible counts with model-specific context capacity.
- **Unknown**: no valid recent usage sample; do not display `0%` or rollover automatically.
- **New session**: a separate, empty conversation, *not* the same chat after compact, *not* a resumed chat, and *not* a fork that inherits full history.
- **Context Capsule**: 300–700 tokens by default, containing current goal, verified changes, decisions, blockers, next steps, references and policies.

## Trigger policy

| Context use | Suggested behavior |
|---|---|
| 0–69% | Observe only; no new agent process |
| 70–79% | Prepare low-cost checkpoint at safe turn boundary |
| 80–89% | Offer fresh-session handoff, or auto-rollover for authorized managed sessions |
| 90%+ | Critical warning; avoid starting additional large turns; prefer prepared handoff |
| Unknown | No numeric threshold, manual option only |

These percentage thresholds are **starting assumptions**, not validated optima. Sample at most once per 10–30 seconds and when usage actually changes meaningfully. Metrics are recorded as `reported`, `estimated` (informational only) or `unknown`.

## Rollover state machine

`NORMAL → PREPARING → READY → STARTING_CHILD → WAITING_ACK → COMPLETED`

Error branches: `FAILED_RECOVERABLE`, `CANCELLED`, `UNSUPPORTED`, `UNKNOWN_USAGE`.

1. Identify project/worktree, provider/model, session ID, active task, permissions and last usage sample. Reject out-of-order or invalid samples.
2. Wait for a safe boundary: no live tool, pending human approval, active streaming turn or conflicting edit ownership.
3. Create **verified checkpoint** using repository branch/commit, changed files, task state, prior decisions, observed tests and blockers. Do not invent successful tests or missing context.
4. Save checkpoint + handoff record to MongoDB (or the explicitly configured SQLite profile) **before** announcing readiness. Redis may publish a hint but owns no durable state.
5. Start a new session only through **supported, verified host interface**, and only where the user authorized such managed launches. Preserve the same project, worktree rules, permission mode, provider and model when available. Do not transfer credentials or secretly widen privileges.
6. Inject a capsule **once** using a one-time handoff ID. The new session acknowledges its session ID and capsule digest.
7. Atomically transfer task ownership/lease, link parent-child session IDs, and mark parent `rolled_over` only after valid acknowledgement.
8. On failure, keep previous session, checkpoint and ownership available. Show ready-to-paste manual handoff; never claim rollover succeeded. No infinite rollover loops.

## Provider capability matrix (verify installed versions)

| Client | Evidence of context | Fresh session control | Default |
|---|---|---|---|
| Claude Code | Official status line JSON: `context_window.used_percentage`, `context_window.context_window_size`, `model.id`, `session_id` | Agent-owned supported CLI launch only after opt-in; existing third-party IDE session cannot be commandeered by status hook | Suggest/manual until managed launch proven |
| Codex | Managed app-server `thread/tokenUsage/updated`, `turn/completed` | Managed app-server `thread/start` creates fresh thread | Auto-managed candidate |
| OpenCode | Plugin events, supported SDK if available; context occupancy needs validation | SDK/CLI when verified; OpenCode 2.x plugin compatibility requires testing | Suggest/manual initially |
| Gemini CLI | `AfterModel` usage metadata/telemetry where available, but cumulative usage is not necessarily context occupancy | Approved new-process startup using supported CLI; `PreCompress` is advisory | Suggest/manual initially |
| Other MCP client | MCP initialize does not guarantee context telemetry | Unknown | Manual handoff |

**Compaction blockers:** Claude `PreCompact` can block proactive compaction; if compaction was attempting to recover after a model context-limit error, blocking may cause failure. Gemini `PreCompress` is advisory only. Do not globally disable compaction or install blocking hooks until fresh-session recovery has been tested. OpenCode's `compaction.auto` configuration can be changed only with backup + user approval. A strict no-compaction preference should halt **new work** and present manual handoff if the provider cannot launch fresh sessions.

## Data model (proposed, not current API)

### ContextUsageSample

`project_id`, `provider`, `model_id`, `session_id`, `observed_at`, `source`, `measurement`, `used_tokens?`, `capacity_tokens?`, `used_percent?`, `sequence?`.

### SessionRollover

`rollover_id`, `project_id`, `parent_session_id`, `child_session_id?`, `task_id?`, `state`, `checkpoint_id`, `context_digest`, `revision`, `created_at`, `updated_at`, `failure_reason?`.

### ContextCapsule

`goal`, `task_id`, `done`, `next`, `blocked`, `decisions`, `source_refs`, `changed_files`, `git_branch`, `git_commit`, `observed_tests`, `permissions`, `handoff_id`.

A new MongoDB unique index on `(project_id, rollover_id)` and conditional revision updates enforce idempotency. SQLite remains feature-parity-capable. Parent session ID and model ID are independently verified; display names never authorize actions. No raw transcript/hidden chain-of-thought/secret in durable capsule.

## Swift repository impact

1. `Sources/OmniMemoCore/Runtime.swift`: optional `model_id`, context sample, parent lineage and rollover state on `AgentSession`; add state transitions and validation.
2. `Sources/OmniMemoCore/StoreBackend.swift`, `MongoBackend.swift`, `SQLiteBackend.swift`: add rollout journal and atomic claim handoff, preserving existing records and backend selection.
3. `Sources/omnimem/RuntimeCommands.swift`: add `om context status`, `om rollover preview|now|status|cancel`; extend safe provider hook ingestion. These are **proposed** commands.
4. `Sources/omnimem/MCPServer.swift`: optionally expose short read-only rollover metadata. Avoid unnecessary tool schema bloat.
5. `Sources/OmniServer/Server.swift` + `LiveHub.swift`: reuse current authenticated REST/WebSocket event bus; emit `context.usage.updated`, `rollover.prepared`, `rollover.created`, `rollover.completed`, `rollover.failed`.
6. `frontend/src/api.ts`, `frontend/src/App.tsx`, `frontend/src/views.tsx`: add separate context bar and next-session lineage. Do not mix with milestone task progress.
7. `scripts/install-global.py`: detection and opt-in install of supported hook/status-line adapter. Preserve existing user's statusLine/settings and backup; if cannot merge, decline with instructions.
8. Tests: telemetry, idempotency, serialization, data retention, rollback, cross-session ownership, actual host integration on pinned versions.

## Security and UX

- **No automatic push** and no Git identity changes. Each GitHub push requires separate user approval using authorized `YanIanZ` credentials.
- Explicit authorization is required for a managed launch. No hidden daemons, no unsupported IDE automation, no raw transcript parsing for context estimates.
- MongoDB is persistent source of truth; Redis event hints optional; no new queues/databases/LLM judge/vector store.
- Keep parent until child acknowledges. Respect in-flight edits and worktree locking; do not auto-create conflicting worktrees.
- Prevent infinite chains: max one child per parent, cap rollovers per hour, cooldown new children.
- React cards show **two distinct fields**: `Task Progress` (milestones) and `Context Usage` (actual provider reports). Unknown stays unknown.

## Acceptance tests

1. Reported Claude 72% prepares a checkpoint at an idle boundary without spawning a provider process.
2. Managed Codex at 80% creates exactly one **empty** child thread after checkpoint persistence; context capsule delivered once.
3. A tool running or approval pending defers session creation.
4. Acknowledgement mismatch or Mongo outage leaves the parent and task ownership intact.
5. Two concurrent rollover requests cannot create two children.
6. Stale/missing/token-total-only measurements do not display numeric occupancy.
7. OpenCode event-plugin incompatibility degrades to manual without hanging the IDE.
8. Missing Redis does not lose handoff; reconnect replays durable events.
9. No prompt transcript or credential written to Mongo/Redis, logs, or checkpoints.
10. Parent/child lineage survives restart, and no loops/repeated first-turn capsules occur.
11. Task progress and context occupancy remain separate and accurate in React.
12. Neither rollover nor handoff creates a commit or push, changes Git remote/author, or skips review.
13. Disable/uninstall restores previous host config, without destroying unrelated hooks or user status lines.
14. Full host-aware recovery is tested on specific installed versions before 'automatic' support is advertised.

## Implementation order

**P0:** Claude reported status-line telemetry → Swift capture → MongoDB/SQLite → Vapor WebSocket → React; manual handoff checkpoint.  
**P1:** Codex app-server owned thread start + child ack + idempotency + rollback.  
**P2:** Claude owned CLI fresh-session launch if validated; OpenCode and Gemini version-specific support.  
**P3:** Strict opt-in compaction protection after real end-to-end tests and accurate usage/cost benchmarks.

### References

- https://code.claude.com/docs/en/statusline
- https://code.claude.com/docs/en/hooks
- https://developers.openai.com/codex/app-server
- https://docs.opencode.ai/docs/plugins/
- https://geminicli.com/docs/hooks/reference/
