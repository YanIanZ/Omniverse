---
name: omnimemo-runtime
description: Configure or diagnose OmniMemo native Swift runtime, Vapor HTTP, React office, and each agent's supported lifecycle adapter (Claude Code plugin, Codex/Gemini hooks, OpenCode plugin).
---

# OmniMemo Swift Runtime — Implementation Workflow

1. Inspect `AGENTS.md` and the current requirements document before changing the runtime. Swift 6 + Vapor 4 + React/TS/Vite is fixed.
2. Detect actual provider, extension points (plugin, hooks, MCP), selected storage profile and current directory permissions. No guessed events.
3. Show a dry-run of config/hook changes and request approval for writes. Back up and merge; avoid overriding users' settings.
4. One supported lifecycle adapter per host (Claude Code: the `omniverse-bridge` plugin, never settings hooks; Codex and Gemini: hooks; OpenCode: its plugin) and the first-prompt context capsule, with per-session idempotency and token cap.
5. `om office` starts or reuses only one Vapor HTTP/WebSocket process. React connects to its scoped API.
6. Verify credentials remain server-side, reject invalid WebSocket origins and report honest unknown status.
7. Perform one-agent -> Mongo checkpoint -> UI WebSocket update -> React card acceptance test.
8. Never push without fresh user approval and verified `YanIanZ` owner/account/email/remote.
