# Validation scope

macOS Apple Silicon, Swift 6.4, MongoDB 7.0.31. Source follows the Swift/MongoDB user amendments to PRD v1.2.

## Recorded outcome (2026-10-18)

19 XCTest passed, 0 failed, 0 skipped with a real MongoDB fixture. Both independent smoke tests passed against the packaged release. Strict Swift format lint and both skill validators passed. Release executable is approximately 23 MiB on this machine; this is artifact size, not RAM usage.

## Automated checks

- XCTest suite with real dedicated MongoDB on loopback port 27019. No mocked persistence.
- Independent Python client uses JSON-RPC stdio, SDK initialize handshake, four tool schemas, save/get/context/checkpoint, restarted-process handoff, scope spoof rejection, secret rejection, source staleness and four response budgets.
- Adapter tests exercise preview/no-op, repeated install/uninstall, existing config preservation, edited managed-entry refusal, nonexistent leaves behind symlink parents and manifest symlink refusal.
- Skill frontmatter validation; strict Swift format lint; release build and packaged executable smoke test.
- Runtime CLI test validates TOML with an independent parser and config roundtrip in staging.

See `SPEC.md` §V for invariants and §B for failures considered during implementation.

## Explicit limits

No live paid Codex/Claude conversation is used. Client names in the wire test are fixtures. There is no measured claim of token ROI, retrieval recall, production crash recovery, database volume relocation, drive ejection, cross-platform support or full PRD completion.

The storage-unavailable test removes the local metadata anchor, not a physical mounted disk. Concurrent-write tests use several driver connections and CLI subprocesses; the server uses single-document atomicity and unique indexes, not multi-document transactions requiring a replica set.

`active` means source hash matched; `agent`, test descriptions and semantic assertions remain claims. Project-scoped MCP filtering does not replace MongoDB authentication or OS-level permissions.
