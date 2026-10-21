# OmniMemo

**Local, shared memory and handoff for coding agents.** Claude Code, Codex, Gemini CLI, OpenCode and any MCP host working on the same project read and write one project memory, see each other in a live Mission Control, and hand work to a fresh session without losing the thread.

- **One binary** (`om`, alias `omnimem`): a CLI and an MCP stdio server, written in Swift.
- **Your machine only.** Storage is MongoDB or SQLite on your disk; the web UI listens on loopback. No cloud service, no LLM or API key.
- **Agents never read each other's private chats.** They share saved records, checkpoints and reported status, nothing more.

> Status: 0.3.0, macOS only. It works daily for its author; expect rough edges and breaking changes before 1.0.

## Contents

- [Features](#features) · [Requirements](#requirements) · [Install](#install) · [Usage](#usage)
- [Connected agents](#connected-agents) · [Storage](#storage) · [Security and limits](#security-and-limits)
- [Documentation](#documentation) · [Contributing](#contributing) · [License](#license)

## Features

- **Project memory over MCP:** four tools (`memory_save`, `memory_get`, `memory_context`, `memory_checkpoint`) and matching CLI commands. Every query is scoped to the project the server was launched in.
- **Compact context:** `om context "task"` returns a token-budgeted capsule (256–16384 tokens, a conservative byte-based estimate) instead of whole transcripts.
- **Evidence, not trust:** records carry agent, branch, commit and file hashes, and become `stale` when their source files change. Likely secrets are rejected before they are stored.
- **Checkpoints and handoff:** save what is done and what is next; another agent, or a fresh session of the same one, picks it up.
- **Mission Control:** `om office` opens a pixel-art office in the browser with live agent cards, a task board, approvals, memory and events.
- **Context rollover for Claude Code:** near the context limit, the `omniverse-bridge` plugin can checkpoint, start a fresh session and hand it a verified capsule (opt-in).
- **Approvals:** agents ask, you decide in the browser with Touch ID or your password. A decision never runs anything or pushes to Git by itself.
- **Optional REA:** a pinned reverse-engineering toolkit exposed as a separate MCP server ([docs/REA.md](docs/REA.md)).

## Requirements

- macOS 13+ (tested on Apple Silicon); Linux and Windows are not supported yet
- Swift 6+ with Xcode Command Line Tools, and Git
- One storage backend: [MongoDB Community](https://www.mongodb.com/docs/manual/administration/install-community/) 7+, **or** none at all with `--backend sqlite`
- For connecting agents globally (`--global`): Python 3.11+ and Node/npm

## Install

```sh
git clone https://github.com/YanIanZ/Omniverse.git OmniMemo
cd OmniMemo
./install.sh --dry-run          # preview: prints the plan, changes nothing
```

Then pick one:

```sh
# No database server: SQLite, and connect your installed agents
./install.sh --setup --backend sqlite --global --with-hooks --project "$PWD"

# MongoDB: start a dedicated loopback server on port 27018, and connect your agents
./install.sh --setup --start-mongo --global --with-hooks --project "$PWD"

# Just the CLI in ~/.local/bin, nothing configured
./install.sh
```

The installer builds a release, puts `om` and `omnimem` in `~/.local/bin` (add it to `PATH` if needed) and never uses `sudo`, edits your shell profile, or installs login services. `--global` registers the MCP server with the agent hosts it detects, backing up each file it changes; `--with-hooks` adds live presence for each host. Everything it adds can be removed again.

Check the result and restart your agents:

```sh
om status
om doctor        # if something looks wrong
```

Full options, supported hosts, backups and uninstall: [docs/INSTALLATION.md](docs/INSTALLATION.md).

Only want the agent skills (instructions, no binary)? `npx skills add YanIanZ/Omniverse`.

## Usage

```sh
om context "add rate limiting to the API"        # what is known before you start
om memory save --kind decision --title "Use token bucket" --content "…" --source src/limit.ts
om checkpoint --done "limiter + tests" --next "wire into router"
om recall "rate limit"                           # search
om office                                        # Mission Control in the browser
om agents                                        # who is working on this project
om tasks add "Review limiter" --priority P1
```

Inside an agent you rarely type these: the MCP tools and the installed skills (`omnimem-recall`, `omnimem-handoff`) let the agent recall and checkpoint on its own. Use `memory save --stdin` to keep text out of shell history. Run `om --help` for everything else.

## Connected agents

| Host | How it connects | Live presence (`--with-hooks`) |
|---|---|---|
| Claude Code | MCP + skills | `omniverse-bridge` plugin: sessions, prompts, tool categories, context use, rollover |
| Codex | MCP + skills | hooks in `~/.codex/hooks.json` (Codex asks you to trust them) |
| Gemini CLI | MCP + skills | hooks |
| OpenCode 2.x | MCP + skills | OmniMemo OpenCode plugin |
| Cursor, VS Code, JetBrains, Xcode, Antigravity, others | MCP | — |

Hooks and plugins fail open: they never block a prompt or a tool call. Only categories are reported (for example "edit" or "shell"), never prompts, tool arguments or secrets.

The Claude Code plugin's options (`rollover`: `off` / `suggest` / `auto`, thresholds, extra context windows) are set in `/config`; see [plugins/omniverse-bridge-mod/README.md](plugins/omniverse-bridge-mod/README.md).

## Storage

Each data directory chooses one profile at `om init`; there is no silent fallback between them.

| Profile | Best for | Where data lives |
|---|---|---|
| `sqlite` | one machine, nothing to run | `<data-dir>/db/memory.sqlite` |
| `mongodb` (default) | several agents and processes, optional Redis live updates | your MongoDB server |

Redis is optional and only speeds up the live UI; it never holds data. Pass credentials through `OMNIMEM_MONGO_URI` / `OMNIMEM_REDIS_URL`, never on the command line. Auto-save is opt-in: `om autosave enable`.

## Security and limits

- Memory is **untrusted data**: agents are told to verify it against the repository. `active` means the source file still matches its hash, not that a claim is true.
- Agent names are labels, not authentication. Anyone with local access to the database or data directory can read it; rely on OS and database permissions.
- Secret detection is heuristic and cannot catch every format. Do not store secrets.
- The server is loopback-only, uses a per-install token, single-use sign-in links, HttpOnly cookies, Origin checks and a CSP.
- Not implemented: cloud sync, LAN access, embeddings, automatic conflict resolution, Linux/Windows.

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Documentation

| Document | For |
|---|---|
| [docs/INSTALLATION.md](docs/INSTALLATION.md) | install options, global hosts, backups, uninstall |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | building, testing, packaging, repository layout |
| [docs/RUNTIME_EVENTS.md](docs/RUNTIME_EVENTS.md) | agent cards, runtime events, context rollover contract |
| [docs/REA.md](docs/REA.md) | the optional reverse-engineering toolkit |
| [docs/VALIDATION.md](docs/VALIDATION.md) | what has been tested, and how |
| [CHANGELOG.md](CHANGELOG.md) | release history |
| [SPEC.md](SPEC.md), [AGENTS.md](AGENTS.md) | the working spec and the rules coding agents follow in this repo |

The other files in `docs/` are the original product requirement and technical specification documents, kept for reference; several describe features that are still proposals.

## Contributing

Issues and pull requests are welcome; start with [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 YanIanZ. Built on the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk), [MongoKitten](https://github.com/orlandos-nl/MongoKitten) and [Vapor](https://vapor.codes).
