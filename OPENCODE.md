# OpenCode — OmniMemo

`AGENTS.md` is canonical. Follow §10: Swift core; Vapor 4 server; React/TypeScript UI; MongoDB+Redis hybrid; auto-wake only on supported agent events; `om` manual fallback; no automatic push and GitHub identity is `YanIanZ`.

Runtime capabilities must be probed against installed OpenCode plugin/API version. Never assume access to private sessions or invent process state. Task capsules must respect project isolation and token budget.

## Multi-agent bridge, Omniverse and runtime events

Follow `AGENTS.md` §§11–13. OpenCode reports real lifecycle and tool activity to OmniMemo through its supported adapter (hooks or plugin); report only categories, never prompts, tool arguments or secrets. Agent cards show `client-model`, current task and honest progress; unknown stays unknown, and silence becomes stale.

## Context rollover

Follow `AGENTS.md` §14. OpenCode near its context limit gets a verified checkpoint and a fresh session only through a supported, authorized interface; otherwise offer manual handoff. Report context usage only from host data; unknown stays unknown.
