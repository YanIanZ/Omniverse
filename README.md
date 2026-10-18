# OmniMemo 0.2.0

Local memory and handoff for coding agents, built with **Swift + MongoDB**, with an optional **Vapor 4** HTTP/WebSocket server and **React + TypeScript + Vite** Mission Control (PRD v1.9 vertical slice). Redis is optional and never stores durable data.

One executable provides a CLI and MCP stdio server. MongoDB stores records; local directories hold storage pointers and disposable caches. Agents working on the same project share its database. OmniMemo does not read private agent histories or require an LLM/API key.

## Mission Control and `om` (v1.9 vertical slice)

`om` is a short alias of `omnimem`. Bare `om` prints status and never starts a server.

```sh
om office            # start or reuse ONE loopback Vapor server, open the React UI
om serve --port 8787 # same server in the foreground
om stop              # stops only the OmniMemo server, never MongoDB/Redis
om recall "query"    # search memory
om agents            # observed sessions; stale presence shows as unknown
om tasks add "Review hook" ; om tasks move <id> doing --revision 1
om --agent claude wake --session <id>
om --agent claude context --first-prompt --session <id>
```

- **Claude Code hooks (opt-in):** `bash install.sh --global --with-hooks` adds `SessionStart`, `UserPromptSubmit` and `SessionEnd` hooks next to any existing hooks. On the first prompt of a session the hook injects one bounded capsule (600 tokens by default); unchanged capsules and empty projects inject nothing. Hooks fail open and never block a prompt. Other hosts use MCP or manual `om` commands; no IDE-open event is assumed.
- **Server:** loopback only; per-install token in `<data-dir>/server-token` (0600); browser login sets an HttpOnly `SameSite=Strict` cookie; Host allowlist, Origin checks for writes and WebSockets, CSP. API: `/api/v1/health|agents|tasks|memory/search|events`, WebSocket `/ws/v1/live`. Task updates require `If-Match: <revision>` and return 409 on a stale revision.
- **Data:** sessions, tasks and events live in MongoDB; events are committed before broadcast. `OMNIMEM_REDIS_URL` (optional) only sends a Pub/Sub hint so the UI updates immediately; without Redis the server polls MongoDB every second.
- **Frontend development:** `cd frontend && npm run dev`, with `om serve --dev-origin http://127.0.0.1:5173`. Release builds copy `frontend/dist` next to the binary; no Node runtime is needed.
- **Not built yet (PRD P1/P2):** approvals, 2D office, Codex/Gemini/OpenCode lifecycle adapters, reconnect history beyond 1000 events.

## REA integration

Version 0.2.0 includes the complete public investigation skill and references from [YanIanZ/rea](https://github.com/YanIanZ/rea), plus a pinned runtime exposing **184 MCP tools, 135 CLI commands, and 6 prompts**. The memory core uses Swift + MongoDB; REA runs through a separate Node runtime using `omnimem rea run` and `omnimem rea mcp`. Installing with `--with-rea` registers both servers and the complete skill. The default profile enables memory only.

```sh
python3 scripts/prepare-rea.py
./scripts/package.sh
/Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem rea status
```

See [REA setup, capabilities, evidence-to-memory workflows, and engine prerequisites](docs/REA.md). Native/runtime tools depend on upstream OS and engine support; every provider has not been tested.

## Features

- Four MCP tools through the official Swift SDK: `memory_save`, `memory_get`, `memory_context`, and `memory_checkpoint`.
- CLI save/search/show/list/delete/export, checkpoint, context, status, doctor, and cache commands.
- Project binding at launch, with every record query filtered by project ID.
- Agent/branch/commit metadata, file-evidence hashes, and `unverified`/`active`/`stale` states.
- Unique indexes for deduplication and idempotency; bilingual text search without stemming and literal code-symbol search.
- Compact context with conservative response limits, including an MCP envelope allowance. The latest checkpoint remains available when task search has no match.
- A default 32 MiB disk cache, 24-hour TTL, and eviction. Keys include current records and evidence; retrieval still checks the database.
- Project-scoped Codex/Claude adapters with preview by default, explicit application, backups, and uninstall that preserves unrelated settings.
- Recall and handoff skills, plus the optional REA skill. Canonical resources live in `Sources/OmniMemoCore/Skills`; `skills` is a distribution symlink.

## Requirements

Tested on macOS Apple Silicon with Swift 6.4 and MongoDB 7.0.31. The package declares macOS 13 as its minimum; that minimum OS has not been tested separately. Linux/Windows are not supported or packaged; hashing currently uses CryptoKit. Swift language mode 5 maintains library compatibility with the Swift 6 compiler.

A running local MongoDB server is required. Swift + MongoDB supersede the original PRD's Rust/SQLite and no-database-service requirements. MongoKitten is used because MongoDB's official Swift driver was archived. The pinned MCP SDK 0.12.1 supports 2025-era handshakes; 2026 protocol compatibility is not claimed.

## Automatic installation

With Swift 6+, Git, and MongoDB already installed on macOS:

```sh
git clone https://github.com/YanIanZ/OmniMemo.git
cd OmniMemo
./install.sh --dry-run
./install.sh
```

The installer builds a release, keeps resource bundles beside the executable, and installs
`~/.local/bin/omnimem`. It uses Ext for caches when available, otherwise the macOS user
cache. It does not edit your shell profile; add `~/.local/bin` to `PATH` if needed.

For automatic memory setup and global registration in detected agent/IDE profiles:

```sh
./install.sh --global --setup --start-mongo --project "$PWD"
# Optional project-only profile with the complete separate REA MCP server:
./install.sh --with-rea --setup --project "$PWD"
```

`--global --setup` also sets the CLI default storage pointer, preserving a backup.
Global installation requires Python 3.11+ and Node/npm for the standard skills installer.
Use `--prefix`, `--cache-dir`, and `--data-dir` for custom locations. An existing MongoDB
server can be selected with `--mongo-uri` instead of `--start-mongo`. Dependencies must
be installed separately; the script does not install Xcode, providers, or login services.
See [installation, supported global profiles, backups, and uninstall](docs/INSTALLATION.md).

## Install skills with npx

The repository works directly with the standard [Agent Skills CLI](https://github.com/vercel-labs/skills):

```sh
npx skills add YanIanZ/OmniMemo --list
npx skills add YanIanZ/OmniMemo
# Global, noninteractive installation for selected hosts:
npx skills add YanIanZ/OmniMemo --global --agent codex claude-code opencode gemini-cli --skill '*' --yes
# From a local checkout; the wrapper pins skills CLI 1.5.12:
./scripts/install-skills.sh --global --agent codex claude-code --skill '*' --yes
```

Available skills: `omnimem-recall`, `omnimem-handoff`, and `reverse-engineer-anything`
(with all six references). Installing skill instructions does not install Swift, MongoDB,
MCP servers, the REA runtime, or external engines. Use the automatic installer for those
OmniMemo components. Universal hosts share `~/.agents/skills`; host-specific links are
created where required by the skills CLI.

## Build

For a fresh macOS clone with Swift and `mongod` available:

```sh
git clone https://github.com/YanIanZ/OmniMemo.git
cd OmniMemo
export OMNIMEM_BUILD_CACHE="$HOME/Library/Caches/OmniMemo/swift"
export OMNIMEM_MONGO_ROOT="$HOME/Library/Application Support/OmniMemo/mongodb"
export OMNIMEM_REA_RUNTIME="$HOME/Library/Caches/OmniMemo/integrations/rea-runtime.json"
./scripts/package.sh "$HOME/Library/Application Support/OmniMemo/bin"
./scripts/mongodb.sh start

BIN="$HOME/Library/Application Support/OmniMemo/bin/omnimem"
DATA="$HOME/Library/Application Support/OmniMemo/data"
PROJECT="$PWD"
"$BIN" --data-dir "$DATA" --project "$PROJECT" init \
  --mongo-uri mongodb://127.0.0.1:27018/omnimemo
"$BIN" --data-dir "$DATA" --project "$PROJECT" status
```

Optional REA support requires a compatible Node/npm installation. Run
`python3 scripts/prepare-rea.py --base "$HOME/Library/Caches/OmniMemo"`, then rerun
`package.sh` to include the local runtime pointer. Keep runtime pointers, databases,
credentials, and build artifacts out of Git. The `/Volumes/Ext` examples below use
the development machine's layout; the overrides above work without that disk.

To build using the development layout:

```sh
cd /Volumes/Ext/MinionsProject/OmniMemo
./scripts/swift.sh build
./scripts/package.sh
```

Default artifact: `/Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem`. Keep the executable and its skill resource bundles in the same directory. Package caches, checkouts, module caches, and build output use `/Volumes/Ext/DevCache/OmniMemo/swift`; set `OMNIMEM_BUILD_CACHE` for another location. No Xcode project or application server is required.

## Getting started

If you do not already have a suitable MongoDB server, start the dedicated OmniMemo instance. The script does not enable a Homebrew login/background service:

```sh
./scripts/mongodb.sh start  # loopback 127.0.0.1:27018; dbPath on Ext

BIN=/Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem
DATA=/Volumes/Ext/DevCache/OmniMemo/data
PROJECT=/Volumes/Ext/MinionsProject/OmniMemo

"$BIN" --data-dir "$DATA" --project "$PROJECT" init \
  --mongo-uri mongodb://127.0.0.1:27018/omnimemo

"$BIN" --data-dir "$DATA" --project "$PROJECT" memory save \
  --kind decision --title 'Storage choice' \
  --content 'Use Swift and MongoDB.' --source Package.swift

"$BIN" --data-dir "$DATA" --project "$PROJECT" context 'storage' --max-tokens 1000

"$BIN" --data-dir "$DATA" --project "$PROJECT" checkpoint \
  --done 'Core implementation complete' --next 'Verify host integration' \
  --tests 'swift test: actual results' --changed-file Package.swift
```

Use `memory save --stdin` to keep input text out of process arguments and shell history. Do not store secrets. Supply credential-bearing URIs through `OMNIMEM_MONGO_URI`; metadata stores a URI without username/password. The MVP accepts `mongodb://`; `mongodb+srv://` is not supported.

Storage resolution: `--data-dir` → `OMNIMEM_HOME` → `~/.config/omnimem/location.json` → `~/.local/share/omnimem`. `init --set-default` explicitly writes a user-level pointer with a backup. Queries, status, and MCP do not initialize a replacement database or directory when storage is missing. MongoDB's port and dbPath are independent of the metadata/cache directory.

## Codex and Claude integration

Initialize the metadata directory, then preview the proposed additions:

```sh
"$BIN" --data-dir "$DATA" --project "$PROJECT" install --agents codex,claude
# After reviewing the preview:
"$BIN" --data-dir "$DATA" --project "$PROJECT" install --agents codex,claude --apply
```

The installer writes `.codex/config.toml`, `.mcp.json`, two canonical skills in `.agents/skills`, and Claude skill shims pointing to the same sources. It targets the selected project and preserves global configuration. Use `--config-root /path/staging` to prepare output for review elsewhere. Each project has a unique server ID; its MCP command is bound to that root and invokes `mcp serve --stdio`. Restart/approve MCP as required by the host. The installer does not run Git hooks or change Git identity.

```sh
"$BIN" --data-dir "$DATA" --project "$PROJECT" uninstall --apply
```

Uninstall removes only entries that still match its manifest. Edited managed entries cause a refusal requiring manual review. Backups remain in the Git-ignored `.omnimemo-installer/` directory, with private directories and mode-600 files. Review backups before deleting them if they contain older sensitive settings. Uninstall before reinstalling with a different host/path.

## Context limits

`--max-tokens` accepts 256–16384; a budget too small for metadata is rejected. `estimated_tokens` is a **UTF-8 byte-based upper bound**, rather than a model tokenizer result. It includes text escaping and the MCP envelope, reserving 64 bytes for the request ID; fixture IDs are shorter. Responses may be substantially smaller than a model's capacity. Host tool/skill declarations are outside this per-response budget and must be measured separately when benchmarking total cost.

No achieved savings percentage, recall@k, RAM, or latency target is claimed. The 32 MiB limit applies only to the cache; database files, WiredTiger journals, logs, backups, and build caches are separate.

## Testing

```sh
./scripts/test-mongo.sh start  # port 27019; dedicated test data
OMNIMEM_TEST_REA_MANIFEST=/Volumes/Ext/DevCache/OmniMemo/integrations/rea-runtime.json \
OMNIMEM_TEST_MONGO_URI=mongodb://127.0.0.1:27019/omnimemo_tests \
OMNIMEM_TEST_ROOT=/Volumes/Ext/DevCache/OmniMemo/test-workspaces \
  ./scripts/swift.sh test

python3 Tests/mcp_smoke.py /Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem
python3.12 Tests/cli_smoke.py /Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem
python3 Tests/rea_smoke.py /Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem
python3 Tests/office_smoke.py /Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem  # needs redis-server on PATH
./scripts/test-mongo.sh stop
```

Version 0.2.0 validation: **35 XCTest cases passed, zero failures, zero skips**, plus eight independent smoke tests (including `Tests/office_smoke.py` for the v1.9 slice) against the packaged release. See [validation scope and results](docs/VALIDATION.md). Python 3.11+ is required for the CLI smoke test's TOML parser; the memory core does not require Python. Individual REA tools retain their upstream dependencies.

Real MongoDB tests cover multiple writer connections, persistence, isolation, deduplication, secret rejection, evidence staleness, cache invalidation, and missing metadata. An independent Python client tests MCP wire behavior and handoff between two subprocesses labeled as Codex/Claude fixtures. These are not live paid conversations with either product. Without `OMNIMEM_TEST_MONGO_URI`, database tests are reported as skipped.

## Trust and MVP limitations

`active` means a source file still matches its hash; it does not prove a semantic interpretation or a test claim. Memory is untrusted data. Agent provenance is a label, not authentication. Project filtering enforces the MCP contract; local processes with direct MongoDB/filesystem access remain subject to database and OS permissions. The instance script binds only to loopback; configure MongoDB authentication and OS permissions for your environment. Secret detection is heuristic and cannot guarantee recognition of every secret format.

Not implemented: transactional MongoDB migration/relocation, physical drive-disconnection recovery, automatic conflict resolution/revision ledgers, graphs, automatic capture hooks, HTTP, complete adapters for all four hosts, embeddings, cloud sync, or ROI benchmarks. Do not move a WiredTiger dbPath while its server is running. Use appropriate MongoDB backup/restore procedures; the cache directory is not a database backup.

The v1.4–v1.9 rules packs are included: v1.4 PRDs, cumulative v1.7–v1.9 PRDs, and technical specs for REA Bridge (v1.5), Omni Reach (v1.6), OmniBias Guard (v1.7), hybrid MongoDB+Redis storage (v1.8) and Swift/Vapor/React (v1.9), with example configs and on-demand skills in `skills/`. The v1.9 P0 slice above is implemented; Omni Agent delegation, REA Bridge, Omni Reach, OmniBias Guard and the P1/P2 Mission Control views remain proposed. Your Swift + MongoDB amendments remain authoritative.

Project rules are in `AGENTS.md`. The original supplied PRD is retained in `docs/OmniMemo_PRD_v1.2_Guardrails.md`, with user amendments recorded in `SPEC.md`. Historical source documents retain their original language. Git uses the owner's configured identity; remote changes and pushes require explicit approval.

## References

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [MongoKitten](https://github.com/orlandos-nl/MongoKitten)
- [MongoDB Swift driver status](https://github.com/mongodb/mongo-swift-driver)
- [Codex MCP](https://developers.openai.com/codex/mcp/)
- [Claude MCP](https://code.claude.com/docs/en/mcp)
