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

## v1.9 vertical slice (2026-10-18)

Implemented PRD v1.9 P0-A/B/C: `om` alias and commands (`wake`, `context --first-prompt`,
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
