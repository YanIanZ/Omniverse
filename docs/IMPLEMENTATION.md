# OmniMemo implementation plan

User-approved PRD, amended by direct instructions: Swift + MongoDB. MVP follows §24.3: four MCP operations, two adapters, two skills. No additional approval ceremony for this local build. Git hooks remain inactive; no commits/pushes.

1. `Models.swift`, `Paths.swift`, `MongoStore.swift`, `DiskCache.swift`: project-bound records, unique dedup keys, index-backed retrieval, explicit initialization, source hashing and secret rejection. Verify persistence/isolation/concurrency against a separate local MongoDB on port 27019 with data on Ext.
2. `Context.swift`, `MCPServer.swift`, CLI commands: conservative output bound, four SDK-handled tools, independent stdio wire client. Verify SDK handshake, stdout purity and save/get/context/checkpoint across process restart.
3. `Adapters.swift`, `skills/`: generate project-scoped Codex TOML and Claude JSON entries. Preview by default; explicit apply with backups. Verify install twice/uninstall, preservation of existing settings and modified entries.
4. Build release, run all tests, document commands, scope and limits. Do not claim full PRD, production security, Windows/Linux compatibility, or token ROI without evidence.

Dependency choices: official MCP Swift SDK avoids custom protocol implementation; MongoKitten is a native asynchronous driver (official Mongo Swift driver archived); ArgumentParser handles CLI validation. Foundation/CryptoKit for files/hash on the current macOS MVP. MongoDB process is explicitly required by the user's database choice; no other resident service.

## REA extension

Pin YanIanZ/rea commit 94153f1c757e07a6d092e00903aa8b125d4a0afa, preserve its complete generated investigation skill and references, and build its locked runtime in the external cache. `REARuntime.swift` validates matching provenance and replaces the Swift process with the upstream Node CLI/MCP using argv. `REACommand.swift` exposes status/run/mcp. `AgentInstaller` records a memory+REA profile, two distinct server identities and every owned skill reference, while default memory behavior remains intact. Validate with the actual 184-tool/6-prompt REA server, real static analysis, CLI exit/result equivalence and evidence-to-memory handoff. No engine installation or global agent setup is performed.
