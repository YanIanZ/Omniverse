# Validation scope

macOS Apple Silicon, Swift 6.4, MongoDB 7.0.31. Source follows the Swift/MongoDB user amendments to PRD v1.2.

## Recorded outcome (2026-10-18)

19 XCTest passed, 0 failed, 0 skipped with a real MongoDB fixture. Both independent smoke tests passed against the packaged release. Strict Swift format lint and both skill validators passed. Release executable is approximately 23 MiB on this machine; this is artifact size, not RAM usage.

## REA 0.2.0 extension

25 XCTest passed, 0 failed, 0 skipped with the real MongoDB and prepared pinned REA runtime, including six new runtime/profile tests. Complete generated REA registrations are launched by the independent integration fixture; the real server advertises 184 tools and six prompts. Static JavaScript analysis, CLI forwarding/nonzero exit equivalence, full skill/reference install/uninstall, and REA-evidence-to-memory handoff pass against the packaged 0.2.0 release. The vendored catalog reports 135 CLI commands; CLI access is delegated without filtering.

Preparation is rerun against the pinned fork and locked dependencies with no agent setup, engine installation or Git hook changes. Swift lint and skill validation remain clean. No commercial disassembler or every-provider conformance result is implied by the real target-free JavaScript fixture.

## Automated checks

- XCTest suite with real dedicated MongoDB on loopback port 27019. No mocked persistence.
- Independent Python client uses JSON-RPC stdio, SDK initialize handshake, four tool schemas, save/get/context/checkpoint, restarted-process handoff, scope spoof rejection, secret rejection, source staleness and four response budgets.
- Adapter tests exercise preview/no-op, repeated install/uninstall, existing config preservation, edited managed-entry refusal, nonexistent leaves behind symlink parents and manifest symlink refusal.
- Skill frontmatter validation; strict Swift format lint; release build and packaged executable smoke test.
- Runtime CLI test validates TOML with an independent parser and config roundtrip in staging.

See `SPEC.md` §V for invariants and §B for failures considered during implementation.

## Automatic and global installation (2026-10-18)

The new source-installer fixture builds and packages the real executable, verifies paths with
spaces, refuses an unrelated launcher, and repeats project setup without losing a saved
memory or changing the managed MCP configuration. Dry-run creates no installation or data.
The standard pinned skills CLI discovers all three skills and installs them for eight
selected hosts in an isolated home, retaining all six REA references.

Global configuration fixtures validate TOML and eight JSON host layouts, preserve unrelated
settings, reject edited managed entries before uninstall, check private backup permissions,
and verify idempotent apply and preserving uninstall. A real independent MCP client launches
the global command in two Git projects sharing one store: cross-project retrieval is denied,
same-project retrieval survives restart, missing storage stays missing, and a non-project cwd
fails without a fallback project.

A real user-level installation registered eleven detected/configured profiles on this machine,
including separate native Xcode Codex/Claude profiles. Existing settings were compared with
private backups. JetBrains AI Assistant's Global path was verified through its supported
settings UI, then registered in `~/.ai/mcp/mcp.json`. Codex's supported `mcp get` recognizes its entry. This verifies registration,
not live agent-chat acceptance in every IDE. Older JetBrains versions can require a Global import; a portable JSON file is prepared. Editor-only installations
such as Sublime Text require an MCP-capable agent/plugin. Default global MCP exposure remains
four memory tools; the complete pinned REA runtime is available through the installed CLI.

The unchanged Swift core was retested: 25 XCTest cases, zero failures, zero skips. The three
original release smoke fixtures and four new installation/distribution/global fixtures pass.
The CLI config-path fixture must receive the real `lib/omnimemo/omnimem` executable: a shell
launcher hands execution to that binary, which correctly registers its own stable path.
ShellCheck and documented shell syntax checks pass. No runtime provider, dashboard, startup
service, Git hook, Git identity, or new push was enabled by these installation tests.

## Explicit limits

Public-source preparation on 2026-10-18 reran all 25 XCTest cases with real
MongoDB and the pinned REA runtime: zero failures and zero skips. A pattern-based
scan of all 65 historical Git blobs found only the intentional private-key header
and dummy credential URI in `CoreTests.swift`; neither contains an actual key or
credential. This scan is a bounded heuristic, not proof that every possible secret
format is detectable. Build output, databases and the local REA runtime pointer
are excluded from the source repository. Upstream REA license and notices remain
included; no external engine or binary release is published by a source push.

No live paid Codex/Claude conversation is used. Client names in the wire test are fixtures. There is no measured claim of token ROI, retrieval recall, production crash recovery, database volume relocation, drive ejection, cross-platform support or full PRD completion.

The storage-unavailable test removes the local metadata anchor, not a physical mounted disk. Concurrent-write tests use several driver connections and CLI subprocesses; the server uses single-document atomicity and unique indexes, not multi-document transactions requiring a replica set.

`active` means source hash matched; `agent`, test descriptions and semantic assertions remain claims. Project-scoped MCP filtering does not replace MongoDB authentication or OS-level permissions.

## Bug-fix pass (2026-10-18)

Fixed: `init` now honors `OMNIMEM_MONGO_URI` before `--mongo-uri`, matching later reads
(previously setup could write metadata for one database while reads used another);
install/REA paths resolve a bare `omnimem` invoked via `PATH` to an absolute executable;
source denylist checks only path components inside the project; `delete`/`export` return
sanitized errors. Results: 27 XCTest passed, 0 failed, 0 skipped (real MongoDB, pinned REA);
`mcp_smoke`, `cli_smoke`, `rea_smoke`, `global_mcp_smoke`, `install_smoke`,
`global_install_smoke`, `skills_smoke` all PASS against a release packaged under
`/Volumes/Ext`. Packaging under `/private/tmp` makes `cli_smoke` fail only because
Foundation's `resolvingSymlinksInPath()` rewrites `/private/tmp` to `/tmp`.

## 0.3.0: Mission Control vertical slice (2026-10-18)

Implemented the Mission Control vertical slice: `om` alias and commands (`wake`, `context --first-prompt`,
`recall`, `agents`, `tasks`, `serve`, `office`, `stop`, `hook claude`); MongoDB sessions, ordered
events and revision-checked tasks; optional Redis Pub/Sub hint (RediStack 1.6.3, tested against
local Redis 8.10.2); Vapor 4.122.2 REST/WebSocket server; React 19 + TypeScript 7 + Vite 8 UI;
opt-in Claude Code hooks in the global installer.

Results: 35 XCTest passed, 0 failed (8 new: runtime idempotency, stale presence, prompt capsule
once-per-change, task idempotency and a two-writer CAS race, Redis outage, server auth/Host/
Origin/CSRF guards, If-Match/409, SPA fallback vs `/api`). All eight smoke tests PASS, including
`office_smoke.py`: Claude-format hook stdin, office reuse (same pid), React served by Vapor,
WebSocket origin/auth/scope denial, live task event in 0.03 s with Redis, Redis outage with
MongoDB writes intact, `om stop`. A Chrome session confirmed cookie login, live task/agent
updates without reload, browser POST/PATCH, and no console errors.

Not verified: a live paid Claude Code session firing the installed hooks (fixtures use the
documented stdin JSON), Codex/Gemini/OpenCode lifecycle hooks, approvals, 2D office, multi-process
server deployment, TLS/remote access (unsupported by design).

## 0.3.0: Agent Office, approvals and host adapters (2026-10-19)

Built: pixel-art Agent Office (original 12x16 sprites; Claude Design canvas "OmniMemo Pixel
Office"), Tasks Kanban with priority and owner, Agents, Approvals (browser-session-only
decisions), Memory and Events views; MCP `initialize` presence with SIGTERM/EOF disconnect;
`om hook claude|codex|gemini|opencode`; `om approvals`; installer hooks for Codex and Gemini.

Results: 36 XCTest passed, 0 failed (new: approval decisions refuse bearer tokens, decide once).
All nine smoke tests PASS, including new `agents_smoke.py` (MCP clientInfo presence, Codex text
capsule once, Gemini `hookSpecificOutput.additionalContext`, OpenCode presence-only events).

Live test with OpenCode 2.0.31 (model `opencode-go/beam-free`; the configured Azure default
failed DNS): OpenCode connected over MCP, claimed the task with `om`, wrote `hello.md`, saved a
checkpoint through the MCP tool, moved the task to review and requested an approval (events
#5-#9 within about 5 s). Screenshots 10 s apart showed the open browser move the agent from
Briefing to Approvals ("Needs you") without reload; intermediate rooms were not captured. A human
Approve in Mission Control moved the agent to Review (`approval.decided`).

Found and fixed during the run: packaging overwrote a signed binary in place (kernel killed it);
MCP sessions stayed `ready` when the host stopped the server with a signal; `index.html` lacked
`Cache-Control` so browsers kept stale builds; map class collision; cramped Kanban controls.

Not verified live: Codex (account rate-limited; fixture-tested with its hook payloads), Gemini
CLI (fixture-tested), Claude Code hooks in a paid session. OpenCode 2.x event plugins stall
sessions in 2.0.31 (a subscribe-only plugin reproduces it), so none is installed for 2.x.

## SQLite profile and auto-save (2026-10-19)

Added the PRD §100 `sqlite` profile behind a small storage interface shared with MongoDB
(`MemoryStore` keeps validation, secret filtering, evidence, dedup, capsules and events; backends
only persist): `db/memory.sqlite`, FTS5 (BM25) plus substring fallback, WAL, busy timeout,
`BEGIN IMMEDIATE` read-check-write for task CAS, approvals and event sequencing. A missing database
file is `storage_unavailable`; nothing is recreated. Opt-in auto-save (FR-15) via `om autosave`.

Results: 44 XCTest passed, 0 failed (6 new SQLite tests: dedup/FTS/substring/reopen/delete, no
shadow database, two connections racing on idempotent create, CAS and approval decisions with
contiguous event revisions, prompt capsule once per change, auto-save opt-in/secret skip/no
capsule inflation/merged repeat checkpoints, porcelain parsing with spaces). A CLI run confirmed
WAL mode and `PRAGMA integrity_check` = ok.

## Omni Agent delegation and design review (2026-10-19)

Work was split into OmniMemo tasks in the real project store and executed by: two Claude
subagents (pixel office detail; data views polish, both with the impeccable skill), two OpenCode
2.0.31 workers on OpenCode Go models (`kimi-k2.7-code` for the map, `glm-5.3` for the views) and a
second Kimi batch, coordinated with `om wake`, `om tasks move` and `om checkpoint`; each task was
moved to done only after integration checks (typecheck, build, Playwright captures at 1440 and
390, zero browser console errors). Mission Control on the real store showed the workers in the
office while they worked, with Redis connected.

Impeccable finish review: round 1 `recapture` (the phone capture was not 390 wide), round 2 `fix`
(seven findings), verdict pass after the fix batch: five resolved, two partial plus three new map
issues. A final map batch addressed those (bubbles kept inside rooms, plates on the room strip,
full-width desktop map, bottom padding); it was checked with captures only, not re-reviewed.

Bugs found by real use and fixed: a signed shift in the sprite palette crashed the page for some
agent names; Vite inlined small fonts as data: URIs that the CSP blocks; duplicate tasks from a
concurrent probe before indexes existed. Full suite after the backend changes: 44 XCTest and all
nine smoke tests passed on a fresh package.

## 0.3.0 release numbering (2026-10-19)

Requirement-document labels (v1.x) were removed from the active rules, README, installation
guide, skills, example configs and tests; features are named instead and OmniMemo is versioned by
its releases. `omnimem --version`, the MCP server version, the default package path
(`dist/0.3.0`) and the frontend package are 0.3.0. Re-run after the change: 44 XCTest passed and
all nine smoke tests passed against `dist/0.3.0/omnimem`.

## Runtime bridge, context rollover and managed Codex (2026-10-19)

Scope: runtime events (v2.3), context rollover P0/P1 (v2.4) and the managed Codex adapter.

- XCTest: 63 passed, 0 failed, 0 skipped (real MongoDB on 27019, REA manifest set). New: `RuntimeIngestTests` (Codex worker) and `ContextRolloverTests`, each on MongoDB and SQLite where it applies.
- Smoke: all nine passed against a fresh package in `dist/next`. `office_smoke` and `agents_smoke` now assert the new status names; `global_install_smoke` covers `--with-statusline`.
- HTTP, curl on SQLite:
  - `POST /api/runtime/events`: 202, then 200 for a duplicate; a disallowed metadata key returns 400.
  - No token 401; foreign `workspace_id` 403; cookie write without Origin 403.
  - `/ws/office`: 101 with Origin, 403 without.
- UI: Playwright at 1440 and 390 (agents, office, memory): no horizontal scroll, no clipped memory cards, zero console errors.
- Live Codex (codex-cli 0.163.0, `om codex run`):
  - One-turn run in 8 s: session, task, prompt, shell tool, context 4.8 %, turn completed and session ended.
  - Timeout interrupt: `turn/interrupt` with `turnId`, then `turn.failed` and exit 1.
  - Managed rollover forced with `--rollover-at 1`, on SQLite and on MongoDB: an empty child thread acknowledged the digest and finished the task from the capsule alone. The task moved to the child and the parent was retired (`rollover.prepared`, `created`, `completed`).

Bugs found and fixed:
- MongoDB session saves could never clear a field. The encoder omits nil, so `$set` kept stale `tool_category` and `task_id`. Fields are now `$unset`.
- `om checkpoint` failed when more than 8 changed files were given, or when one was missing. Evidence is now capped at 8 existing files, and the full list stays in the checkpoint content.
- Checkpoints in the Memory view showed as raw JSON because the API cut them at 240 characters.
- Long unbroken paths widened memory cards past the column.

Not verified or not implemented:
- The OpenCode 2.x plugin wiring for `tool.execute.before/after`. The OpenCode Go quota was exhausted during this run, and the local plugin types are 1.x.
- Fresh-session launch for Claude Code, OpenCode or Gemini.
- Compaction guards.
- Claude status-line capture in a live Claude session: tested with recorded status-line JSON only.

Multi-agent run: tasks and capsules went through the OmniMemo store.
- Codex (`codex exec`, about 94k and 96k tokens) wrote the runtime tests and docs, and the context UI with the installer opt-in.
- OpenCode Go `glm-5.3` stopped on its usage limit before editing anything; Claude did that task.
- Each result was reviewed and re-verified before its task was marked done.

## OpenCode 2.x tool hooks and the Claude Code mod (2026-10-19)

- OpenCode 2.0.32, live with a free model (`opencode run --standalone`):
  - A probe plugin confirmed the v2 shape: `export default { id, setup(ctx) }`, `ctx.tool.hook("execute.before"/"execute.after")` with `{ tool, sessionID, status }`, `ctx.session.hook("prompt"/"context")`, the `session.execution.*` and `session.step.ended` events from a detached `ctx.event.subscribe`, and `ctx.model.list()` limits.
  - The generated plugin recorded session, prompt, shell tool (`execute`), context 5.3 % and offline on shutdown.
  - A run with the plugin loaded exits normally; it no longer stalls as in 2.0.31.
- Claude Code mod (`plugins/omniverse-bridge-mod`):
  - `claude plugin validate` passed, and a strict `tsc` against the 2.1.302 engine types passed.
  - `claude plugin test`: 5 tests passed. They cover the handoff through `/om-rollover` (checkpoint first, capsule replaces the compaction, Claude's own summarizer not reached, one ACK prompt), auto mode with ACK completed or failed, and suggest mode never compacting.
  - Found by the tests: the engine refuses a compaction from a `command.run` hook, and a plugin's own `$.session.compact` skips its own hook.
  - Changed afterwards (user's choice): the handoff now uses `/clear` for a fresh session id instead of a compaction. That adds `om rollover begin|link` and `report --child`, and the mod tests now number 7: checkpoint before the one-child reserve, the new session getting the capsule once, ACK moving the task, no second child, a refused `/clear` changing nothing, suggest mode.
  - Not run yet inside a live Claude Code session: it loads after a restart.
- XCTest: 66 passed (+3: OpenCode tool names, in-place rollover report on SQLite and MongoDB). Smoke: all nine passed; `global_install_smoke` now expects the v2 plugin.
- Activated on this machine:
  - `om` 0.3.0 reinstalled.
  - Global profile re-applied with `--with-hooks`: Claude 7 hook events, Codex 5, OpenCode v2 plugin.
  - The mod is loaded via `CLAUDE_CODE_PLUGIN_DIRS` with `rollover: auto`. `settings.json` was backed up under `global-install/backups`.
  - Mission Control was restarted on the new binary.
  - This Claude session appeared live through the hooks before any restart.
