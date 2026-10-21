# Installation

The source installer supports macOS with Swift 6+, Git, and a running MongoDB server.
`mongod` is required only when starting the dedicated instance. REA preparation additionally
requires Python 3 and compatible Node/npm (22.19+, 24.11+, or 26+). Global host setup requires
Python 3.11+ for TOML validation and Node/npm for `npx skills`. Missing dependencies produce
an actionable error; no `sudo`, package-manager installation, provider login, or login service
is performed.

## CLI and project setup

Run `./install.sh --help` for options. Installation stages a release before replacing an
installer-owned copy. A failed build preserves the previous executable. The wrapper lives
at `PREFIX/bin/omnimem`; binaries and resources live at `PREFIX/lib/omnimemo`.
Unrelated files and edited launchers are refused rather than overwritten.

```sh
./install.sh --prefix "$HOME/.local"
./install.sh --setup --start-mongo --project /absolute/path/to/project
./install.sh --setup --mongo-uri mongodb://127.0.0.1:27017/omnimemo \
  --project /absolute/path/to/project
./install.sh --with-rea --setup --project /absolute/path/to/project
```

`--setup` explicitly initializes storage and applies project adapters. Without it, installation
only installs the executable. `--start-mongo` requires `--setup` and uses loopback port 27018
with a dedicated dbPath. It starts a local process, not a login service; use
`scripts/mongodb.sh stop` with the same `OMNIMEM_MONGO_ROOT` to stop it. The root defaults
to the selected install cache plus `/mongodb`. A failure in project setup does not remove
an otherwise successfully installed CLI or database; inspect the reported failure and retry.

Paths passed as options must be absolute. Credentials belong in `OMNIMEM_MONGO_URI`, not
`--mongo-uri` or a checked-in script. Project-only installation preserves your default storage-location pointer.
`--global --setup` explicitly sets that pointer with the core initializer's backup behavior,
so the installed CLI uses the selected store by default. Otherwise keep passing
`--data-dir`, set `OMNIMEM_HOME`, or use `init --set-default` explicitly. Generated MCP entries
already contain the selected data directory.

## Global hosts

```sh
./install.sh --global --setup --start-mongo --project /absolute/path/to/project
# Preview or repeat the global configuration step independently:
./scripts/install-global.sh \
  --binary /absolute/prefix/lib/omnimemo/omnimem \
  --data-dir /absolute/data \
  --state-dir /absolute/cache/global-install
# Add --apply --install-skills to apply that preview and run npx.
```

`--global` detects installed executables/applications and existing supported host profiles.
It merges user-level MCP settings and installs the three skills with the standard pinned
skills CLI. It preserves unrelated server entries, account settings, and global instructions.
It does not copy credentials between hosts, grant trust, activate hooks, launch provider
workers, enable a dashboard, or read private transcripts. Restart each host and approve its
MCP servers as required. Registered configuration is distinct from a tested live agent session.

| Host/profile | Global configuration |
| --- | --- |
| Codex CLI/extension | `$CODEX_HOME/config.toml`, default `~/.codex/config.toml` |
| Claude Code and its IDE extension | `~/.claude.json` user `mcpServers` |
| Gemini CLI | `~/.gemini/settings.json` |
| OpenCode | `$XDG_CONFIG_HOME/opencode/opencode.json`; version-detected v1 `mcp` or v2 `mcp.servers` |
| VS Code | `~/Library/Application Support/Code/User/mcp.json`, with workspace cwd |
| Antigravity | `~/.gemini/config/mcp_config.json`, or the existing legacy path if present alone |
| Cursor | `~/.cursor/mcp.json` when installed/configured |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` when installed/configured |
| GitHub Copilot for Xcode | `~/.config/github-copilot/xcode/mcp.json` |
| Xcode native Codex | `~/Library/Developer/Xcode/CodingAssistant/codex/config.toml` |
| Xcode native Claude | `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude.json` |
| JetBrains AI Assistant | `~/.ai/mcp/mcp.json`, verified as the Global destination in the installed AI Assistant settings; older profiles can import `jetbrains-global-import.json` through that UI |
| Other editors, including Sublime Text | Use an installed supported agent, or an MCP-capable plugin with the generated portable configuration; editor presence alone does not provide an MCP client |

Xcode native profiles use their own settings and skills, separate from terminal-agent profiles.
The JetBrains path was verified through the installed 2025.3.3 AI Assistant UI; additional versions/profiles can require their own setup. JSONC/commented configurations are
refused for automatic modification; review them manually rather than losing comments. Existing
OpenCode v1 entries are retained when adding a v2 server map; automatic legacy migration is
outside this installer. If both old and new Antigravity config files exist, the modern path
is used; verify the active path in that host's raw-config view.

The default global memory profile exposes four tools. `--with-rea` also registers the separate
full REA server and prepares its runtime; it increases the available tool/schema surface.
New detected hosts can be added idempotently. Changing an existing host's server/binary/data/REA profile requires its managed uninstall first. REA can also
be used through the CLI without exposing its 184-tool MCP catalog globally.

## Project isolation

Each global server process uses its **launch Git root**, or an explicitly configured
`OMNIMEM_PROJECT`. It never uses the installation repository as a universal project.
Memory remains filtered by the bound project ID even though projects share storage.
The global launcher neither initializes missing storage nor selects a default project.
If a GUI host starts in a non-project directory, set that server's working directory to
its project or configure `OMNIMEM_PROJECT` for that host. VS Code receives `${workspaceFolder}`
as its MCP working directory. Project-specific installer entries remain available for hosts
that cannot provide a workspace directory. No arbitrary IDE-session control is claimed.

## Backups and removal

Global state is stored under the selected cache's `global-install`. Its directory and backups
are private (700/600). Backups may contain pre-existing account settings; keep them local and
out of Git. An entry-only manifest supports safe repeat installation and uninstall. Conflicting
managed entries fail before configuration changes; writes are staged, and files changed since
planning cause a refusal. Concurrent writes by unrelated host processes cannot be guaranteed
transactional across all configuration files; avoid editing settings during installation.

```sh
./scripts/install-global.sh --state-dir /absolute/cache/global-install --uninstall
./scripts/install-global.sh --state-dir /absolute/cache/global-install --uninstall --apply
```

Uninstall removes only unchanged managed MCP entries, preserving unrelated additions. It leaves
backups, skills, the executable, database, and memory intact. Remove skills separately with
`npx skills remove omnimem-recall omnimem-handoff reverse-engineer-anything --global` after
reviewing which hosts use them. Native Xcode skill links and canonical shared skills require
separate review/removal. Remove the installer-owned executable only after uninstalling entries
that refer to it. Never remove a live MongoDB dbPath as part of uninstall.

## Supplied requirement documents

The supplied requirement documents in `docs/` are kept unchanged as references, with
archive/member hashes in `rules-v1.4-provenance.json` (the name is the supplier's document
number, not an OmniMemo release). Their Rust examples are historical: OmniMemo is Swift, with
MongoDB or the explicit SQLite profile. The active repository rules include their safety
policies. `omni-agent.example.toml` is a proposed configuration, not a working delegation engine.
OmniMemo 0.3.0 coordinates agents through tasks, revisions and approvals; it does not launch
provider sessions.

## Agent hooks and Mission Control

`--with-hooks` (only with `--global`) wires lifecycle presence through each host's own extension
point, each ending in `<binary> --data-dir <data> hook <host>`. Claude Code gets no settings hooks:
the installer adds the install directory as the `omnimemo` plugin marketplace and installs the
`omniverse-bridge` plugin for the user (`claude plugin install omniverse-bridge@omnimemo`), which
reports session, prompt, tool and turn events from the plugin's own engine events and attaches the
context capsule to the prompt; uninstall removes it. When `$CODEX_HOME` points somewhere other
than `~/.codex`, the Codex desktop app (which always reads `~/.codex`) is its own host,
`codex-app`, with the same MCP entries and Codex hooks. Hooks are written for Codex
`$CODEX_HOME/hooks.json` `SessionStart`, `UserPromptSubmit`, `Stop` (trust them when Codex asks);
Gemini CLI `~/.gemini/settings.json` `SessionStart`, `BeforeAgent`, `AfterAgent`, `SessionEnd`
(the same file as its MCP entry; both are merged in one write). OpenCode 1.x receives
`plugins/omnimemo.js`; OpenCode 2.x receives no plugin because a plugin subscribing to events
stalled sessions in 2.0.31, so its presence comes from the MCP connection. Existing hooks are kept; a preview runs
first; uninstall removes only the OmniMemo entries and refuses edited ones. Restart Claude Code
after installation. An `--home` fixture run never touches the real Claude Code plugin list. The hook resolves the Git root of the session's `cwd`; outside Git, or when
storage is unavailable, it does nothing and exits 0.

`om office` starts one loopback Vapor server per project, on the first free port from 8787
(`servers/<project-id>.json`, `server.log` and the shared `server-token` live in the data
directory), and reuses it on later calls from that project; `om stop` stops this project's server,
`om stop --all` every project's. Each server's browser cookie is named after its port, so signing
in to one project never signs you out of another. Set
`om redis enable` (or `OMNIMEM_REDIS_URL`) only if a Redis server is already available; OmniMemo
never configures, flushes or stops Redis or MongoDB. Set `OMNIMEM_DEBUG=1` to print the
underlying database error of a failed command to stderr (never in MCP or HTTP responses).

## Primary host references

- [Agent Skills CLI](https://github.com/vercel-labs/skills)
- [Codex MCP](https://developers.openai.com/codex/mcp/)
- [Gemini MCP](https://geminicli.com/docs/tools/mcp-server/)
- [OpenCode v2 MCP](https://dev.opencode.ai/v2/docs/mcp-servers/)
- [VS Code MCP configuration](https://code.visualstudio.com/docs/agents/reference/mcp-configuration)
- [Antigravity MCP](https://antigravity.google/docs/mcp)
- [Xcode agent environments](https://developer.apple.com/documentation/xcode/extending-and-customizing-agents)
- [Copilot for Xcode MCP config location](https://github.com/github/CopilotForXcode/blob/main/Core/Sources/HostApp/ToolsSettings/MCPConfigConstants.swift)
- [JetBrains AI Assistant MCP](https://www.jetbrains.com/help/ai-assistant/mcp.html)
