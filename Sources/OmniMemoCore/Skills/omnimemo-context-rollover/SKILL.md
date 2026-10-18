---
name: omnimemo-context-rollover
description: Prepare a verified bounded checkpoint for a clean new agent session near context capacity, using only authorized supported runtimes.
---

# Omni Context Rollover Skill

Implemented (suggest/manual mode):
- Claude Code reports context usage through `om statusline claude` (opt-in status line). `om runtime sessions` and Mission Control show it as `context`, separate from task progress; no recent sample means `unknown`.
- `om rollover preview` prints a bounded capsule (tasks, unverified milestones, git branch/commit, changed files). `om rollover prepare` saves it as a checkpoint first, then prints it with a handoff id.
- Managed Codex only (opt-in): `om codex run --rollover` starts an empty app-server thread after a completed turn at the threshold, delivers the capsule once, requires `ACK <digest>`, then moves the task; without the acknowledgement the parent keeps it.

- Claude Code with the Omniverse mod: `rollover` `auto` (or `/om-rollover`) answers a marked `/compact` with the capsule alone, asks once for `ACK <digest>`, and records the outcome. This is a same-session reset, not a new session id.

Not implemented: rollover for OpenCode or Gemini; compaction guards.

1. Use reported active context usage only; never infer it from lifetime tokens.
2. Wait for a safe turn boundary: no running tool, pending approval or conflicting edit.
3. Run `om rollover prepare` (optionally `--session <id>`), then start a fresh session yourself and paste the capsule. Keep the original session until the new one has picked up the work.
4. Never copy full chat, secrets or private reasoning into a capsule.
5. No automatic commit/merge/push. Authorized YanIanZ account and human approval for every push.
