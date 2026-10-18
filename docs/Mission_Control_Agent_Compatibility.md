# OmniMemo — Agent Integration Compatibility Plan

**Never promise identical automatic hooks across providers.** Probe installed versions and supported config APIs on each user's machine.

| Agent | MCP memory | Session activation | Before first prompt | Cross-agent handoff |
|---|---|---|---|---|
| Claude Code | Adapter planned | Use supported `SessionStart` when available | Use supported `UserPromptSubmit` when available | Via scoped OmniMemo Task Capsule |
| Gemini CLI | Adapter planned | Probe installed hook support | Probe installed pre-agent hook | Via MCP/CLI |
| Codex | Adapter planned | Probe installed client version and supported hooks | MCP-first-use or hook if supported | Via MCP/CLI |
| OpenCode | Adapter planned | Probe event/plugin API | Use official plugin event if supported | Via MCP/CLI |

If a host doesn't expose an IDE-open event, auto-activate on session/MCP first-use or approved `om run` wrapper; do not read private app databases or automate an IDE without supported APIs. Actual status is `unknown` without heartbeat/event; provider name does not imply agent role.
