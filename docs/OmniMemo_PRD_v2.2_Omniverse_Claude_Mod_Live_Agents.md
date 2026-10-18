# OmniMemo v2.2 — Omniverse Claude Mod & Live Agent Cards

**Status:** implementation proposal + minimal read-only reference mod. **Supersedes:** the decision in v2.1 to build a Claude Code terminal replacement. **Preserves:** OmniMemo memory, Omni Agent, Multi-Agent Bridge, Swift 6/Vapor, React, MongoDB, Redis, OmniBias Guard, Omni REA, Omni Reach, GitHub YanIanZ policies, and CLI `om`.

## 1. Product decision

Omniverse is now a **Claude Code Mod/Plugin** and interoperable **cross-IDE bridge**, not a Claude Code fork, code copy, or replacement terminal. Claude Code remains the official client, other agent applications remain their native clients. The first deliverable is agent presence and task progress; task handoff is a subsequent phase.

Omniverse bridge: Swift 6 server via Vapor, REST + WebSocket, Redis for ephemeral presence/events, MongoDB for persistent tasks/memory. React Mission Control is the full office UI. Claude Code Mod renders a compact agent list in a pane or slash-command result and reads only authorized local API responses. No new web runtime or frontend stack for the terminal.

The official Claude Code Mods API (released 2026-10) supports in-process UI/commands; the mod is non-sandboxed and must be audited before loading. Never copy Claude Code proprietary implementation. Sources:
- https://code.claude.com/docs/en/plugins/mods
- https://code.claude.com/docs/en/plugins/mods/api
- https://code.claude.com/docs/en/plugins/mods/interface
- https://github.com/anthropics/claude-code/blob/main/LICENSE.md

## 2. Agent card UI (P0)

Exact layout in both interfaces:

```text
opencode-kimi-k2.7-code                            REVIEWING
Review phone fixes 1.3
████████████░░░░░░░░ 60% · 3/5 checkpoints complete

claude-opus-5.5                                  RUNNING
Analyze authentication architecture
████████░░░░░░░░░░░░ 40% · 2/5 checkpoints complete

codex-gpt-6                                      WAITING
Implement fixes after review
░░░░░░░░░░░░░░░░░░░░ 0% · Blocked on review
```

These names, models, tasks and percentages are **fictional examples**. They do not assert model availability or agent presence. UI text must not imply verification when data is inferred or user-supplied.

Visible fields:
1. **Name — Model:** canonical slug `client-model`, e.g. `opencode-kimi-k2.7-code`; from runtime reported model identifier, normalized for display. If model cannot be established: `opencode-model-unknown`.
2. **Current Task:** safe task title from explicit task metadata; never auto-publish raw prompt contents. Example: `Review phone fixes 1.3`; if missing: `No active task`.
3. **Progress Bar:** determinate if a work plan has weighted, independently checkable milestones; otherwise indeterminate indicator with no number.
4. **Status:** `working`, `reviewing`, `waiting`, `blocked`, `done`, `idle`, `offline`, or `unknown`. Status derives from actual adapter signals and heartbeat TTL; UI must not invent them.
5. **Details on expand:** stage checklist, code branch/worktree, agent runtime, task dependency, last update, source of progress, evidence links, permissions and handoff history. Hide secrets and raw conversations by default.

### Identity
- Canonical `display_slug` = `<client>-<normalized-model-id>`. `client` in `codex|claude|opencode|gemini|other-approved` and model is read from registered adapter, **not** assumed from session nickname.
- Separate immutable `agent_instance_id` (UUID), `session_id`, `workspace_id`, `provider_id`, `model_id`. Never authorize based on slug; slug is not unique and not proof of provider authenticity.
- Two same slugs in one workspace display `#2`, `#3` or shortened session labels; identity still by UUID.
- When model switches, retain same agent instance and task identity but update display slug; event `agent.identity.updated` tracks change.
- Truncate display labels for narrow terminals; full label available on selection. Never leak user email or local absolute paths.

## 3. Progress semantics (P0)

**Core rule:** Never display model reasoning progress as task percentage.

For a defined plan with N checkpoints and numeric positive weights:
`progress = 100 * sum(weight_i for verified completed i) / sum(weight_i for all i)`.
Default equal weights. Completed means evidenced by a trusted task update or test; text saying "I think I'm done" without evidence stays unverified. Display percent rounded to an integer and `completed/total` separately.

- `working` with no accepted plan: animated indeterminate bar; label `Working — progress unknown`.
- `waiting`: freeze last confirmed progress and show dependency; stale/offline markers are separate.
- `blocked`: freeze progress and show blocker + owner.
- `done`: 100% only if all required milestones complete and acceptance checks pass; unverified agent self-report -> `awaiting_verification` or `reviewing`, **not** 100%.
- Replanning changes denominator and is stored as a new `plan_revision`; preserve history, explain an apparent drop.
- If no heartbeat inside configurable TTL (~45 seconds default), label `offline` and show last update, not `running`.
- Progress may stall while work proceeds; do not guess percentage from time, tool calls, tokens, number of files, LLM self-estimate, or spinner duration.
- UI must display `progress_source` (`checkpoint`, `host_signal`, `manual_verified`, `unknown`) and `updated_at` for diagnosis.

### Example checklist
For `Review phone fixes 1.3`:
1. Inspect changes — completed, verified.
2. Identify regressions — completed, verified.
3. Validate phone-specific behavior — completed, verified.
4. Run target tests — in progress.
5. Submit reviewed findings — pending.
At equal weight, confirmed progress = `3/5 = 60%`. Sample only.

## 4. Client/UI requirements

### Claude Code Mod (primary user request)
- When `/om-agents` is invoked, open a compact agent pane and retrieve current status through signed/authenticated local bridge HTTP. If bridge is unavailable, show `Bridge unavailable` instead of fake agents.
- In the initial reference implementation, `/om-agents` is read-only; future `/om-send <agent-id> <task>` creates a proposal and **does not run commands remotely** until the target side accepts according to permissions.
- Refresh no more frequently than every 10-15 seconds in terminal (adjustable); event-driven React WebSocket is the richer, immediate experience. Avoid per-frame HTTP requests, extra background model calls or automatic raw conversation uploads.
- A status line may show just `3 agents · 2 active · 1 blocked` to minimize noise; `/om-agents` reveals full cards.
- Min-width: narrow terminal => 1-line name, 1-line task, 10-cell bar or `working…` fallback.

### React/Vapor Mission Control
- Cards update through authenticated WebSocket events, backed by snapshot GET and monotonic `sequence` values to detect missed messages.
- Agent/task data isolated per authorized project and local workspace.
- Support filtering by workspace, agent, status, task; expand stages; pause rendering when tab hidden.
- Render same semantic state as Claude Mod; never compute different percentages in frontend.

## 5. API data contract (planned; not yet implemented)

`GET /api/v1/agents` returns:

```json
{
  "schema_version": 1,
  "sequence": 87,
  "agents": [
    {
      "agent_instance_id": "0192-EXAMPLE-NOT-A-UUID",
      "client": "opencode",
      "model_id": "kimi-k2.7-code",
      "display_slug": "opencode-kimi-k2.7-code",
      "workspace_id": "example-workspace",
      "status": "reviewing",
      "task": { "id": "task-123", "title": "Review phone fixes 1.3" },
      "progress": {
        "kind": "determinate", "completed": 3, "total": 5,
        "percent": 60, "source": "verified_checkpoints", "plan_revision": 1
      },
      "last_heartbeat_at": "2026-10-19T01:00:00+07:00"
    }
  ]
}
```

All sample IDs and timestamps are illustrative; runtime must emit real IDs/time and must authorize results by workspace. `progress.kind` is `determinate | indeterminate | unavailable` and percent must be `null` unless determinate. The server, not the frontend or mod, validates percent. JSON wire version must be incremented for breaking changes.

WebSocket event `agent.snapshot`, `agent.status.changed`, `task.progress.changed`, `agent.identity.updated`, `agent.offline`, `handoff.proposed`, `handoff.accepted`, and `handoff.denied` share `sequence` and `timestamp`. Reconnect pulls snapshot to resolve gaps.

## 6. Security and Git identity

- Bind HTTP to loopback by default, require randomly generated token for local clients, do not log or transmit token, redact prompts/secrets from descriptions; enforce origin protection for browser writes.
- Mod may read session metadata but must not send full transcripts, prompt text, credentials, model hidden state or history without explicit user authorization.
- The mod must not approve tool calls, change Claude Code permissions, silently execute remote tasks, or persist browser cookies.
- Never push without user approval; verified GitHub account `YanIanZ`, verified author/committer email, allowed remote, no AI co-author trailers by default.
- Models display labels are untrusted metadata, not a security boundary. All mutating endpoints enforce policy independently.
- Keep MongoDB the source of truth, Redis for ephemeral coordination, no new broker/database.

## 7. Minimal delivery plan and acceptance

**P0:** Swift/Vapor `GET /api/v1/agents`, model registration, plan-based progress, Claude mod `/om-agents`, React agent cards, offline mode. **P1:** cross-IDE task proposal/accept; checklists and expand view. **P2:** animation/personalization/graph insights only if useful.

Acceptance:
1. OpenCode `opencode-kimi-k2.7-code`, task and 3/5 progress render identically in Claude pane and React.
2. Model switch updates label without creating a second agent.
3. Two same model sessions get distinct instance IDs; optional UI discriminator.
4. Unknown plan => indeterminate bar with no numeric percentage.
5. At TTL expiry status changes from active to offline even if 60% complete.
6. No agent reported? Empty state, never mock cards in production.
7. Malicious/untrusted agent names cannot authorize commands or inject markup.
8. Mutating handoff asks appropriate permission; Git push still forbidden without user approval.
9. No extra model invocation to obtain progress; record token and runtime overhead in benchmarks.
10. `claude plugin validate` passes on supported local Claude Code version before release; mod smoke tested on real Vapor server.

## 8. Compatibility note

This package is a *blueprint and example mod*, not a working Omniverse/Vapor deployment. The reference mod expects a future `/api/v1/agents` backend, and its Claude Code integration has **not** been validated against a local Claude installation. Validate host Mods API compatibility against the installed version before use.
