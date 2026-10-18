# Omniverse Bridge Claude Mod — Experimental UI skeleton

Displays (1) `client-model`, (2) current task, (3) progress bar in an `/om-agents` pane. This is original example code using public Claude Code Mods hooks. It neither modifies Anthropic code nor replaces the Claude Code terminal. Source: https://code.claude.com/docs/en/plugins/mods

**Backend:** `om serve` exposes the authenticated `GET http://127.0.0.1:8787/api/runtime/sessions` (`{workspace_id, agents:[...]}`). Cards appear only for agents that sent runtime events (see `docs/RUNTIME_EVENTS.md`).

**Local usage after auditing:**
1. Set `OMNIMEMO_BRIDGE_TOKEN` securely in your shell/session environment. Never paste it into chat, code, Git, or screenshots.
2. `claude plugin validate ./plugins/omniverse-bridge-mod`
3. `claude --plugin-dir ./plugins/omniverse-bridge-mod`
4. Within Claude Code enter `/om-agents`.

The mod polls every 15 seconds for a bounded agent list, never invokes a model, never writes state, and displays empty/error states honestly. UI/compatibility **not tested** on a local Claude installation. Do not load unreviewed mods: they run with the user's filesystem and network permissions. Tests must use a real Claude version.

Tasks/handoffs are **future features**, not implemented by this read-only scaffold. Add mutation endpoints only with explicit human approval, workspace authorization, and native client capability detection.
