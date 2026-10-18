---
name: omnimemo-multi-agent-bridge
description: Use when coordinating Codex, Claude Code, Gemini CLI, OpenCode or other coding agents across separate IDEs/terminals through OmniMemo, for task handoff, inbox pickup, capability checking or Mission Control live presence.
---

# Omni Multi-Agent Bridge — cross-IDE handoff

1. Read root `AGENTS.md` and `docs/Omni_Multi_Agent_Bridge_Technical_Spec_v2.0.md` before implementation or setup.
2. Detect provider + version + supported hooks/MCP/SDK abilities; do not infer ability to control existing IDE sessions.
3. Share short task capsules with file scopes, acceptance criteria, evidence refs and budget, not full chat histories or secrets.
4. Use MongoDB-backed task inbox and atomic claims for reliable work. Redis only for best-effort live notifications; retry/reconcile from MongoDB after disconnect.
5. Use `om bridge` commands for manual operation or a verified host hook for opt-in automatic session registration/first-prompt context injection.
6. Keep one worker by default and never permit competing edits to the same worktree; review is read-only unless explicitly authorized.
7. Stream honest observed state to Vapor WebSocket/React; never synthesize fake working status, provider outputs, model costs or success metrics.
8. Never commit or push without appropriate grants; per-push human approval and owner `YanIanZ` Git identity verification are mandatory. Avoid changing Git config or Git hooks automatically.
9. Test Codex -> Claude -> OmniMemo -> Codex end-to-end before adding other adapters or extra infrastructure.
