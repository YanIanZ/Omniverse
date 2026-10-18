---
name: omnimemo-runtime
description: Configure or diagnose OmniMemo native Swift runtime, Vapor HTTP, React office, and supported agent auto-start hooks.
---

# OmniMemo Swift Runtime — Implementation Workflow

1. Inspect `AGENTS.md` and v1.9 PRD before changing runtime. Swift 6 + Vapor 4 + React/TS/Vite is fixed.
2. Detect actual provider, hook/MCP capabilities, selected storage profile and current directory permissions. No guessed events.
3. Show a dry-run of config/hook changes and request approval for writes. Back up and merge; avoid overriding users' settings.
4. Implement only one supported startup hook and first-prompt context capsule, with per-session idempotency and token cap.
5. `om office` starts or reuses only one Vapor HTTP/WebSocket process. React connects to its scoped API.
6. Verify credentials remain server-side, reject invalid WebSocket origins and report honest unknown status.
7. Perform one-agent -> Mongo checkpoint -> UI WebSocket update -> React card acceptance test.
8. Never push without fresh user approval and verified `YanIanZ` owner/account/email/remote.
