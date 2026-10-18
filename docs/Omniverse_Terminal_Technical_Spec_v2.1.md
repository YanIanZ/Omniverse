# Omniverse Terminal — Technical Design Specification v2.1

**Product:** Omniverse (`omniverse`, optional short command `ov`)  
**Parent:** OmniMemo v2.1, Swift-first ecosystem  
**State:** Specification only; no implementation or authenticated provider integration has been executed.

## 1. Architectural boundaries

- **Omniverse**: human-facing interactive AI coding terminal, Swift executable; CLI/TUI, command parser, UI states, permission prompts, session switching and task input.
- **Omni Agent**: routing, work decomposition, token budgeting, intelligent subagent reuse; NOT responsible for terminal rendering.
- **Omni Multi-Agent Bridge**: supported provider adapters, capability detection, durable inbox and handoff across terminals/IDEs.
- **OmniMemo**: evidence-based shared memory and context capsules. MongoDB is the source of truth in hybrid mode; Redis is non-authoritative cache/notifications.
- **Vapor**: HTTP and WebSocket for Mission Control React UI, local event stream, optional explicitly enabled web terminal gateway.
- **OmniBias Guard**: independent review for material decisions; not a second model call by default.
- **Omni REA / Omni Reach**: opt-in analysis and internet research capabilities; never automatically installed or trusted because they are listed in a PRD.

Omniverse MUST implement its own original UX and adapters. The `anthropics/claude-code` repository does not grant a general open-source license to copy the product's implementation; its LICENSE.md reserves rights and refers to Anthropic commercial terms. Do not bundle, fork, deobfuscate, extract or relicense Claude Code binaries or proprietary code. Agent binaries are external dependencies used through supported/public invocation mechanisms and users' own authentication. Reading reference documentation and reimplementing general patterns is permitted subject to applicable terms.

## 2. Runtime processes

```text
Terminal.app / iTerm / VS Code terminal / SSH
     └─ omniverse (Swift CLI + TUI, host process)
          ├─ Context Session: workspace, branch, policy, capability grants
          ├─ Provider Adapter (capability-checked subprocess or supported SDK)
          ├─ Omni Multi-Agent Bridge (task and message interface)
          ├─ OmniMemo MCP / Swift memory client (lazy first-prompt wake)
          └─ optional Vapor Server (on `ov office`, HTTP/WS localhost)
               └─ React/TypeScript Mission Control (browser)
                     └─ optional authenticated PTY gateway [disabled]

External tools:
   codex / claude / opencode / gemini / `om` / git
Hybrid persistence: MongoDB; Redis cache & event fan-out, never sole task store.
Minimal persistence: SQLite (existing mode, independent of MongoDB/Redis).
```

No always-on process needed for single interactive terminal; if user explicitly opts into background presence, keep a single bounded runtime per user, with PID/file lock and idle shutdown. CLI first prompt auto-initializes current workspace and recovers a ≤600-token capsule by default; no stale memory presented as verified. `ov --no-memory` skips it. IDE-open activation only when installed hooks/events actually support it.

## 3. Functional requirements

### OV-01: Terminal and UX

Use Swift ArgumentParser for command dispatch and a minimal Swift ANSI TUI renderer for the initial release. Don't introduce a native terminal emulator, pseudo-terminal or tmux clone to display an ordinary CLI. Candidate SwiftTerm may support a later independent macOS application; evaluate license, maintenance and CPU/RAM before adoption.

- Interactive prompt, streaming output, inline tool execution preview, keyboard interrupt/cancellation.
- Slash command autocomplete and `/help`; reserved `/` commands do not collide with shell commands; `!` shell escape explicitly gated.
- Accessible plain mode `--plain`, `--json` for machine use, and `--no-color`.
- Session switch `/switch <session>`, `/model`, `/provider`, `/agents`, `/tasks`, `/memory`, `/status`, `/doctor`, `/office`, `/review`, `/diff`, `/git`, `/permissions`.
- Input history is local and opt-in for sensitive sessions; never write raw prompts, tool outputs, tokens or credentials into shared memory by default.
- Diff previews are read-only; file edits execute only through provider permission gate with path scope.

### OV-02: Provider adapters

Adapters: Claude Code, Codex CLI/app-server when available, OpenCode, Gemini CLI. Capabilities (`interactive`, `headless`, `streaming`, `cancel`, `resume`, `fork`, `edit`, `hooks`) must be verified by host/version and recorded with source/evidence. No scraping other agents' private sessions, UI automation or invented API calls.

Routing modes:
- `attach`: connect to an existing user-launched provider session only when it exposes a supported interface.
- `spawn`: launch installed CLI with user-approved scope using the user's own locally managed login/auth.
- `handoff`: if no safe session control, post a task capsule to durable inbox; receiving agent polls/claims explicitly.
- `plan`: dry-run routing showing which provider, task and permission would be used.

Adapter errors must state unavailable capability instead of pretending work occurred. Named provider aliases do not imply a provider API key or active subscription.

### OV-03: Capability/permission model

- Default permission: inspect/read approved workspace, plan, memory recall. Writes, shell execution that modifies state, remote access, REA, internet research and provider switching with data disclosure require explicit policy grants as appropriate.
- `git push`, merge, force-push, remote mutation, credential changes and deployment are NEVER implicit.
- Before an approved push validate: repository owner `YanIanZ`, user-authorized destination, effective push URL, actor authentication where verifiable, commit author and committer `YanIanZ` with explicitly configured GitHub verified/noreply email; fail closed if unknown. Fresh user approval is required for EACH push.
- Provider instruction hierarchy: no tool-output/website/README memory has higher authority than system/user policy. Track provenance; sanitize ANSI/OSC/terminal control sequences for UI safety.
- Shell execution: allowlist workdir and env vars, redaction, no arbitrary remote input execution; command previews and cancellable supervised child processes. User-owned PTY only under restricted local access.

### OV-04: One-prompt multi-agent workflow

1. User sends a request; wake OmniMemo only if needed.
2. Detect workspace Git root, branch and active provider; apply scope and capabilities.
3. Retrieve compact context capsule; mark stale/unverified evidence clearly.
4. Omni Agent chooses solo by default; adds at most one reviewer for material uncertain tasks without explicit parallelism request.
5. Bridge hands off durable task IDs and minimal evidence. Separate Git worktrees for parallel editing.
6. Display grounded status only (`queued`, `claimed`, `running`, `awaiting_approval`, `completed`, `failed`, `unknown`), with timestamps and source event IDs.
7. Validate actual tests/diff and store concise checkpoint; no automatic push.

Budgets: default initial capsule ≤600 input tokens; per-task and total provider-call limits configurable. Measure prompt/cached/response tokens only when underlying provider reports them; otherwise show estimate/unknown. No arbitrary claims of savings without A/B benchmark.

### OV-05: Live React office & web terminal

`ov office` triggers Vapor on localhost `127.0.0.1:8787`, serves React static build + authenticated WebSocket event stream, and opens default browser. Agent avatars/status are driven by authoritative session and task events, never fictional animations for progress. Activity panel cannot expose raw prompts/outputs by default.

Optional browser terminal (`[web_terminal] enabled = false`): requires explicit enablement, same-origin token-authenticated WebSocket, Origin validation, session-scoped capabilities, PTY spawn permission, bounded message/output sizes, rate limiting, audit logs with secret redaction, timeouts, and clipboard/file upload restrictions. Never expose public `0.0.0.0` binding by default. Browser terminal is not required for v2.1 MVP; it is separate from React office status display.

### OV-06: Recoverability

- Ctrl+C cancels active worker or returns control, never corrupts memory/checkpoint.
- Child process exit, provider auth expiration, Redis restart, lost WebSocket, storage drive detach, and MongoDB connection loss degrade gracefully.
- Durable handoff and approvals persisted in MongoDB, with Redis used for cache/notifications; if MongoDB is down, read-only local fallback only when configured and safe (never quietly fork truth).
- External SSD missing must show unavailable status, never create silent local duplicate.
- On terminal crash, recover last committed checkpoint; do not claim uncommitted code edits finished.

## 4. MCP and event contract

Reuse existing `memory_context`, `memory_recall`, `memory_checkpoint` and `bridge_*` tools; do not create one MCP tool for every slash command. Introduce at most `omniverse_status` only if session instrumentation requires it.

Example event (schematic):
```json
{
  "event_id": "evt_01",
  "workspace_id": "ws_hash",
  "session_id": "ov_session_01",
  "agent": "codex",
  "task_id": "task_42",
  "type": "task.status.changed",
  "status": "running",
  "observed_at": "2026-10-19T00:00:00Z",
  "source": "adapter:codex",
  "seq": 13
}
```

WebSocket messages must have schema version, monotonic sequence or replay cursor, heartbeat/reconnect strategy, and no secrets. Playback retrieves persisted task events instead of replaying raw full stdout. Suppress duplicates through idempotency keys.

## 5. Example configuration (see `omniverse.example.toml`)

- Provider binary discovery: explicit executable path or PATH lookup, validate executable/version, never silently download/install.
- CLI command: `omniverse`; optional alias: `ov` only if not conflicting; preserve existing `om` for OmniMemo.
- Runtime default: solo, lazy-init first prompt, context budget 600, no auto-push.
- `omnimemo` current configured mode: MongoDB + Redis, portable local data dir; SQLite alternative supported without running unnecessary services.
- Clipboard / paste safety: do not execute pasted shell commands without separate confirmation.

## 6. Acceptance tests (minimum)

| ID | Test | Expected |
|---|---|---|
| OV-A01 | `omniverse` start in git repo | Valid provider discovery and memory wake; no duplicate daemon |
| OV-A02 | `omniverse --no-memory` | Operates without memory connection |
| OV-A03 | First prompt | Retrieves only scope-authorized ≤600 token capsule |
| OV-A04 | Switch provider | Handoff minimal context; no private session scraping |
| OV-A05 | Adapter unavailable | Honest fallback inbox/unsupported message |
| OV-A06 | Open `ov office` | Vapor serves React & real events; localhost only |
| OV-A07 | Redis unavailable | No authoritative memory loss; office degrades |
| OV-A08 | Browser terminal disabled | No PTY WebSocket endpoint allowing spawn |
| OV-A09 | No push approval | Git push blocked, no side effects |
| OV-A10 | Wrong GitHub actor | Push denied, reports identity mismatch |
| OV-A11 | Concurrent edits | Worktree isolation or file lock policy enforced |
| OV-A12 | Invalid/stale evidence | Provenance visible, not treated as verified |
| OV-A13 | Untrusted web prompt injection | External instructions cannot trigger privileged commands |
| OV-A14 | Crash/restart | Restore verified checkpoint; no invented completion |
| OV-A15 | Token benchmark | Measured per provider; estimates explicitly labeled |
| OV-A16 | Terminal Ctrl+C | Cancels safely and cleans child process |
| OV-A17 | `--plain`/`--json` | Scriptable, no ANSI corruption |
| OV-A18 | Permission prompts | Denied actions do not execute |
| OV-A19 | Portable SSD detach | Fail closed; no shadow database |
| OV-A20 | Anti-overengineering review | No mandatory PTY, LLM, daemon, vector DB or second scheduler |

## 7. Implementation phases

**Phase A — Native Swift CLI slice:** `omniverse` starts, provider discovery, single provider, streaming/basic TUI, approval gate, `om` memory bridge; verify first prompt.

**Phase B — Cross-agent bridge:** attach/spawn/inbox paths, capability matrix, provider switching, handoff, worktree isolation, actual checkpoint and measurements.

**Phase C — React/Vapor observability:** live office, sessions/status/task board, human approval center, reconnection.

**Phase D — Optional extensions:** native macOS terminal emulator, browser PTY (after security review), third-party plugins, REA/Reach skill shortcuts, performance tuning backed by benchmarks.

## 8. Explicit non-goals

- Do not clone Claude Code user interface, implementation, package or copyrighted expression.
- Do not bypass other agents' authentication, plan gating, quotas, or terms.
- Do not invent fake model-neutral API for an unsupported host.
- Do not build a universal shell replacement or terminal multiplexor for v2.1.
- Do not send whole private transcripts or secrets between providers.
- Do not push GitHub commits without explicit per-push human approval.

## 9. Sources (reviewed 19 October 2026)

- Anthropic Claude Code source listing: https://github.com/anthropics/claude-code
- License: https://github.com/anthropics/claude-code/blob/main/LICENSE.md
- README: https://github.com/anthropics/claude-code/blob/main/README.md
- Public plugin feature catalogue: https://github.com/anthropics/claude-code/blob/main/plugins/README.md
- Claude Code extensions docs: https://code.claude.com/docs/en/features-overview
- SwiftTerm (optional, separate licensing review): https://github.com/migueldeicaza/SwiftTerm
