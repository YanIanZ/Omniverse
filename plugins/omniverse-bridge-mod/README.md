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

## The handoff: a fresh session

1. `om rollover prepare` saves the capsule as a checkpoint first: tasks, unverified milestones, git branch/commit and changed files.
2. `om rollover begin` reserves the only child of this session. A session that already handed off gets no second one.
3. The mod runs `/clear`. The conversation ends and Claude Code continues under a new session id with an empty context; nothing of the old conversation is carried over.
4. `om rollover link` records parent → child.
5. One prompt delivers the capsule into the new session, with the person's last request (up to 1200 characters, never stored). Its first line must be `ACK <digest>`.
6. With the acknowledgement, `om rollover report --child` moves the task to the new session and retires the parent (`rollover.completed`).
   - Without it, the parent keeps the task (`rollover.failed`) and stays resumable with `claude --resume <parent id>`.
   - If `/clear` is refused, the session is unchanged and the checkpoint stays saved.

## Load it

For every session: add the folder to `CLAUDE_CODE_PLUGIN_DIRS` in the `env` block of `~/.claude/settings.json` and restart Claude Code. For one session: `claude --plugin-dir plugins/omniverse-bridge-mod`. Set options in `/config`, or in settings under `pluginConfigs["omniverse-bridge"].options` (for example `{ "rollover": "auto" }`).

The mod runs with your permissions (it calls `om` through `$.process`); review it before loading. Checks:

```sh
claude plugin validate plugins/omniverse-bridge-mod
claude plugin test plugins/omniverse-bridge-mod
```
