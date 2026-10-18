# OmniMemo MVP-1

## §G
Persist scoped evidence-backed memories; save → retrieve → cross-agent checkpoint via CLI/MCP, local SSD.

## §C
User corrections: Swift + MongoDB replace Rust + SQLite/FTS5. Earlier offline/no-service constraints superseded for local MongoDB.
PRD v1.2 §24.3 supersedes earlier MVP breadth: 4 MCP tools; 2 adapters (Codex/Claude); 2 skills.
One Swift binary; MongoDB text indexes; official Swift MCP SDK; no HTTP server, embeddings, auto-capture or cloud. Local MongoDB required by user override.
External build/package cache. No global config changes or Git identity mutations. User requested local Git version control; commits use existing owner-configured identity. No push.
Source pack rules remain repository-scoped. Missing storage never silently recreated. Cache independent of persistent records.
Relocation/graph/conflict resolution advanced engine deferred to MVP-2/3; evidence/stale flags + isolation required now.

## §I
I.cli: init, status, doctor, project attach, memory save/search/show/list/delete/export, context, checkpoint, cache info/clear, install/uninstall.
I.mcp: memory_save, memory_get, memory_context, memory_checkpoint over stdio; authorized project bound at launch.
I.storage: --data-dir > OMNIMEM_HOME > pointer JSON > OS default. Only init creates datastore.
I.adapters: install --agents codex,claude --project PATH --config-root PATH; preview default; --apply explicit; backup + exact owned-entry uninstall.

## §V
V1: Two independent processes share durable committed records; MongoDB unique indexes hold with concurrent writers.
V2: Store reads/writes restricted to canonical launch root; spoofed project/scope and symlink source escapes rejected.
V3: Secret-bearing memory rejected before persistence; errors/logs never echo raw rejected data.
V4: Evidence hash captured; changed/deleted sources flagged stale; claims without evidence unverified.
V5: Context returns valid JSON and byte-conservative token upper bound <= max_tokens, including MCP content/envelope overhead allowance; low budget rejected explicitly.
V6: Missing DB/volume returns storage_unavailable; status/query/MCP never initialize empty replacement.
V7: Save is atomic + deduplicated by project/kind/body/branch; idempotency retries preserve record, conflicting reuse rejected.
V8: MongoDB text + literal symbol retrieval handles arbitrary query punctuation safely; empty query gives recent checkpoint/decisions.
V9: MCP negotiation + four core tool schemas verified through independent client processes; stdout protocol-only.
V10: Cache quota/TTL bounded; fingerprint-invalid results discarded; cache clear never deletes memory.
V11: Adapters preserve unrelated config; explicit apply; repeated install/uninstall idempotent; edited owned config refuses unsafe uninstall.
V12: Export/delete scoped; delete removes indexed record/cache; metadata provenance retained on saved memories.
V13: Root binding rechecked; source reads + storage resources bounded; future DB schema refused.

V14: Installer checks existing ancestors before creating config leaves; symlink parents cannot escape config root.
V15: Generated Codex config is valid TOML, including quoted paths; uninstall detects changed entries.

## §T
id|status|goal|cites
T1|x|MongoDB core, identity/scope/evidence/FTS/cache + CLI|V1,V2,V3,V4,V6,V7,V8,V10,V12,V13,I.storage,I.cli
T2|x|Bounded context + official MCP stdio + wire tests|V5,V9,I.mcp
T3|x|Two adapters + recall/handoff skills + config roundtrip tests|V11,I.adapters
T4|x|Integration tests, release build, reproducible docs and handoff|V1,V2,V3,V4,V5,V6,V7,V8,V9,V10,V11,V12,V13

## §B
id|date|cause|fix
B1|2026-10-18|Volume root not writable; source location preflight needed|Use writable MinionsProject/OmniMemo; no product invariant

B2|2026-10-18|Swift driver pool existential lacks disconnect; logger factory overloaded|Use concrete optional MongoCluster shutdown and explicit logger factory; existing V9 covers stdout

B3|2026-10-18|Foundation symlink resolution skips nonexistent leaves; adapter escaped root|V14; resolve existing ancestor before write
B4|2026-10-18|JSONEncoder slash escapes are invalid TOML and hid managed-entry edit in test|V15; disable slash escaping for TOML strings
B5|2026-10-18|Skill body dedup moved templates to resources without target resource declaration|Declare bundled Skills resource; adapter roundtrip test exercises lookup
B6|2026-10-18|Swift format lint rejects snake_case stored properties|Use idiomatic Swift names with explicit CodingKeys; preserve JSON/BSON contract
B7|2026-10-18|Release compile overlapped a model-field rename and saw mismatched modules|Serialize final source edits and verification; rerun release after tests
