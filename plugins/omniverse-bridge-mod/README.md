# Omniverse bridge — Claude Code mod

A Claude Code mod (function hooks, Claude Code 2.1.302+) for OmniMemo. It runs the local `om` CLI and needs no server or token.

- `/om-agents` opens a pane of agent cards: `client-model · STATUS`, current task, verified-milestone progress (indeterminate without milestones) and reported context usage.
- The status line reads `OmniMemo · 3 agents · 2 working · 1 blocked · ctx 42%`.
- After each main turn it reports the session's context usage (`$.session.usage()`, the same numbers as Claude's status line) to OmniMemo.
- Context rollover, set with `rollover` (`/config`):
  - `suggest` (default): saves a checkpoint at `prepareAt` (70 %), and at `rolloverAt` (80 %) suggests `/om-rollover`.
  - `auto`: at `rolloverAt`, it runs the handoff below by itself, at most 3 times an hour.
  - `off`: reports usage only.
- `/om-rollover` runs the handoff now.

## The handoff

1. `om rollover prepare` saves the capsule as a checkpoint first: tasks, unverified milestones, git branch/commit and changed files.
2. The mod runs Claude Code's own `/compact`, marked `omnimemo-rollover`, and answers that compaction with the capsule alone, plus the person's last request (up to 1200 characters, never stored). No summary of the old conversation is carried over.
3. One prompt asks the model to reply `ACK <digest>` on its first line and then continue.
4. `om rollover report` records `rollover.completed` or `rollover.failed`.

This is a same-session reset: the session id stays the same, the transcript file keeps the history, and the context window starts from the capsule. If the acknowledgement is missing, the checkpoint stays in OmniMemo for a manual handoff.

## Load it

For every session: add the folder to `CLAUDE_CODE_PLUGIN_DIRS` in the `env` block of `~/.claude/settings.json` and restart Claude Code. For one session: `claude --plugin-dir plugins/omniverse-bridge-mod`. Set options in `/config`, or in settings under `pluginConfigs["omniverse-bridge"].options` (for example `{ "rollover": "auto" }`).

The mod runs with your permissions (it calls `om` through `$.process`); review it before loading. Checks:

```sh
claude plugin validate plugins/omniverse-bridge-mod
claude plugin test plugins/omniverse-bridge-mod
```
