# OmniMemo Hybrid Storage — Technical Specification v1.8

**Status:** Proposed / implement after approval. No code tested against running MongoDB or Redis.  
**Scope:** Single-machine AI-agent client with optional external MongoDB and Redis services, supporting Codex, Claude, Gemini, OpenCode, REA, Reach, Bias Guard and Mission Control.

## Decision record (ADR-018)

- **Chosen**: MongoDB is canonical persistence; Redis is optional acceleration, status signaling and ephemeral presence. MongoDB-only on Redis outage; SQLite retained as explicit lightweight profile.
- **Avoid**: multi-master writes, automatic SQLite write fallback, Redis-only durable tasks/approvals, introducing Kafka/Neo4j/Elasticsearch/Vector DB, background microservices, complex event sourcing for P0.
- **Why**: preserves cross-agent memory and task correctness without adding a distributed transaction across MongoDB and Redis.
- **Non-goal**: replacing MongoDB/Redis configuration for other applications; automatic setup/hosting or production cluster administration.

## Components

```text
MCP / Agent Skills
    | memory_save/recall/context/checkpoint
Memory Guardian + OmniBias + ACL (unchanged)
    | backend abstraction selected once per process
    +-- SqliteBackend (standalone)
    +-- MongoBackend (mongo or hybrid)
             | canonical records, graph, tasks, approvals
             +-- RedisAcceleration (hybrid)
                     | cache, presence, invalidation, optional events
```

The `MemoryRepository` abstraction SHALL remain small: basic operations `save`, `get`, `search`, `update_status`, `checkpoint`, `task_claim`, `task_complete`. Introduce a separate cache trait only when needed by a real second implementation; avoid abstraction-heavy generic repository factories. Compatibility adapters must not bypass ACL or bias evaluation.

## MongoDB collection sketch

### `memories`

```json
{
  "_id": "mem_01J...",
  "workspace_id": "ws_local",
  "project_id": "sha256:repo-identity",
  "scope": "project",
  "branch": "main",
  "kind": "decision",
  "content": "Example technical decision",
  "content_hash": "sha256:...",
  "status": "supported_inference",
  "revision": 3,
  "provenance": [{"kind":"git", "commit":"abc123", "path":"src/lib.rs"}],
  "created_at": "2026-10-18T00:00:00Z",
  "updated_at": "2026-10-18T00:00:00Z"
}
```

Validation: project and workspace from server-side authorized session; `content` bounded in bytes; reject embedded credentials; permit only well-defined statuses. Add indexes only for observed queries, begin with project/status/time and project/hash. Avoid unique dedup indexes that prohibit legitimate distinct decisions sharing identical text. For large collections prefer pagination and tight projection (no full-doc scan per request).

### `tasks`

```json
{
  "_id": "task-104",
  "project_id": "p1",
  "status": "running",
  "revision": 4,
  "attempt": 1,
  "owner_agent": "codex-session-uuid",
  "lease_token": "random_nonce",
  "lease_until": "2026-10-18T22:30:00Z",
  "idempotency_key": "task-104:review",
  "approval_id": null
}
```

Use `findOneAndUpdate` with an explicit filter on `status`, `revision`, lease expiry and caller's project scope, and updates `$set` + `$inc`. A losing client receives `CONFLICT` and refreshes state. `task_complete` must verify both lease token and revision. Write operations requiring user approval remain blocked until an independent verified owner approval record exists. Watch clocks and use an authoritative server-side time strategy, not unbounded client-supplied times.

## Cache-aside and token policy

1. Scope-check caller before generating any key.
2. Hash `(workspace, project, scope, request fingerprint, context max_tokens, authorization profile, revision stamp)`; do not include secrets.
3. Attempt bounded Redis cache lookup with timeout. Redis timeout becomes a miss, NOT task failure.
4. On miss, read MongoDB with constrained projection, apply evidence/bias checks, rank, enforce max_tokens including citations.
5. Optionally cache sanitized result with TTL and byte cap. No raw REA/Reach output, credential, or private cross-project record.
6. On write, commit MongoDB first; invalidate local process cache; best-effort notify Redis.
7. If Redis invalidation is missed, TTL + revision-based validation ensure bounded staleness; material claims cannot be upgraded merely by cached status.

Avoid scanning Redis `KEYS *`; maintain scoped key inventory if bounded namespace deletion is required, or use carefully cursor-scanned `SCAN` with matching prefix and strict batching. Never call `FLUSHALL`/`FLUSHDB` against user's existing Redis.

## Redis key scheme

```text
omnimemo:v1:<env>:<workspace-hash>:<project-hash>:context:<fingerprint>:<revision>
omnimemo:v1:<env>:<workspace-hash>:<project-hash>:presence:<agent-id>
omnimemo:v1:<env>:<workspace-hash>:<project-hash>:invalidate
omnimemo:v1:<env>:<workspace-hash>:<project-hash>:events
```

Cache profiles default to context TTL 900s; presence TTL 60s; events disabled in MVP or Pub/Sub for best-effort UI signal. Redis server maxmemory settings are managed by the operator only; never mutate when sharing it with other services. Redis Streams (P1) must be bounded and acknowledgment conditional on successful canonical state transition.

## Example failure handling

| Condition | Behavior |
|---|---|
| Redis not reachable | Circuit-break short attempts; MongoDB remains operational; local cache optional |
| Mongo not reachable | Reject persistent writes and task leases; visible storage error |
| Transient Mongo write failure | Retry with safe idempotency where supported; never blindly double-create |
| Mongo committed + Redis notify failed | Success for durable write, degraded notification warning |
| Redis cache has old revision | Read Mongo canonical revision and ignore invalid cache |
| Agent crash after claiming task | Lease expires, retry bounded and idempotent |
| SSD path detached | No new shadow database; diagnostic tells exactly what's unavailable |

## External SSD nuance

Existing MongoDB deployments own their own data files and recovery. `omnimem relocate` cannot move a running MongoDB/Redis volume. For local self-hosting, assistance consists of documented backup/stop/move/reconfigure/restore verification with user consent; for remote services, nothing is moved by OmniMemo. Only OmniMemo-controlled config/cache files are immediately portable. Retain original location until verified restoration.

## Security & CI

- Use env vars or OS keychain for `OMNIMEMO_MONGODB_URI` and `OMNIMEMO_REDIS_URL`; keep example file secret-free.
- Use connection timeouts and TLS for remote access; do not bind MongoDB/Redis publicly by default.
- Strict project/workspace ACL is applied before query and cache access; cache keys may not override ACL.
- Scrub credentials and third-party documents from diagnostic logs.
- CI integration tests: isolated Mongo + Redis fixtures, run `db-t01`–`db-t20`; skip with clear notice if services absent; never claim success without running them.
- `gh` / git push operations require owner-authenticated `YanIanZ` account and per-push approval; Redis notification or Mission Control checkbox is not sufficient by itself.

## Phased implementation plan

1. **P0 / existing local setup**: config selection, Mongo connection, core memory CRUD, provenance/scope, indexes, tests. No Redis dependency yet.
2. **P0 / Redis performance**: cache-aside, TTL, namespace and read-only `storage doctor`, graceful fallback, scoped invalidation, metrics.
3. **P0 / Omni Agent task state**: Mongo atomic lease, idempotent checkpoints, worker recovery, no auto-push.
4. **P1 / optional**: Redis Streams, Mongo change streams, migration tools, dashboard advanced metrics. Add only if benchmark/use case justifies.

## Benchmark criteria

Measure warm/cold recall latency, writes, scoped cache hit rate, memory RSS of OmniMemo core separate from DB servers, Redis memory and AOF separately, SSD footprint per datastore, cross-agent consistency, context token footprint, DB outage behavior and recovery. Do not promise fixed 30% savings without a real baseline.

**Links:** https://www.mongodb.com/docs/drivers/rust/current/ · https://www.mongodb.com/docs/manual/core/index-ttl/ · https://www.mongodb.com/docs/manual/changestreams/ · https://redis.io/docs/latest/develop/data-types/streams/ · https://redis.io/docs/latest/develop/reference/eviction/
