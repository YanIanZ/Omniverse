# Changelog

Notable changes to OmniMemo. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/) (pre-1.0: minor versions may break things).

## Unreleased

## 0.3.0 - 2026-10-22

First public release.

### Added
- `om` CLI alias, Vapor HTTP/WebSocket server and React Mission Control with a pixel-art agent office, task board, approvals, memory and events.
- SQLite storage profile beside MongoDB; opt-in auto-save; approvals with Touch ID or password.
- Host adapters: Codex and Gemini hooks, OpenCode 2.x plugin.
- Runtime events, agent cards, managed Codex runs and context rollover.
- Global installation for detected agent hosts and skills via `npx skills`.
- Claude subagents appear as their own sessions linked to their parent, with their context use; Codex and OpenCode can be used as Claude subagent types, delegated read-only through `om`.
- One Mission Control server per project; readable CLI output in a terminal.
- Claude Code presence and context rollover through the `omniverse-bridge` plugin (no settings hooks).
- Contributor docs: `CONTRIBUTING.md`, `SECURITY.md`, `docs/DEVELOPMENT.md`, issue and pull request templates, CI.

### Fixed
- A rollover acknowledged on the first line of the child's reply is recorded as completed even when the turn ends with tool work and a summary.
- A session resumed after a completed rollover can roll over again.
- Stale and offline sessions leave the office at once; a CLI agent is shown once, not again as its MCP presence.
- Redis resubscribes after a dropped connection.
- A new data directory under a symlinked path (such as `/tmp` or `/var` on macOS) is usable right after `init` in the same process.
- Hardening of the bridge, server authentication, storage and guard hooks from code review.
- Build and test scripts work on machines without the maintainer's external disk.
- Mission Control builds from its TypeScript sources; stale compiled `.js` files are no longer committed beside them.

Earlier work in this release: the Swift + MongoDB memory core (MCP tools `memory_save`, `memory_get`, `memory_context`, `memory_checkpoint`, CLI, project isolation, evidence hashes, secret rejection, compact context, disk cache) and the complete pinned REA runtime as a separate MCP server and skill.
