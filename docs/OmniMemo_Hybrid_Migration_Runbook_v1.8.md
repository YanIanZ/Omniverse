# OmniMemo v1.8 — Migration and Operations Runbook (DESIGN ONLY)

## 1. Preflight

1. Identify which deployment is owned by the user: local `mongod` / container / remote instance, Redis dedicated or shared, SQLite file if used.
2. Backup existing OmniMemo SQLite data first. Never manipulate another application's Mongo collections or Redis keys.
3. Verify Mongo authentication, approved dedicated database, schema permissions and network/TLS; report deployment topology and whether transactions/change streams are supported.
4. Verify Redis connectivity and dedicated namespace; *do not* call `FLUSHDB`, `FLUSHALL`, or global CONFIG SET.
5. Verify available disk space on chosen volume, storage backup path and rollback path. Redact DSNs and credentials in dry-run output.

## 2. Existing MongoDB+Redis users

- Choose `hybrid` mode; set `OMNIMEMO_MONGODB_URI` and `OMNIMEMO_REDIS_URL` outside repo.
- Request explicit authorization before creating a new dedicated MongoDB database and indexes or writing any new Redis namespace.
- Do not modify MongoDB/Redis services or install new servers merely to attach OmniMemo.
- Initial schema has `memories`, `entities`, `edges`, `evidence`, `tasks`, `checkpoints`, and `approvals`, using idempotent index creation.
- Check with `omnimem storage doctor` (command planned, not implemented).
- Run a fake/synthetic test memory write, recall, cache miss/hit, then clear only that test data.

## 3. SQLite → MongoDB migration (planned CLI)

1. Freeze OmniMemo writes (do not stop the database server or other applications).
2. Take source snapshot (SQLite backup API or file copy only when safe).
3. Export a versioned NDJSON manifest including records/edges/revisions/ACL/provenance.
4. Run schema validation, dedup and restore counts/hashes; reject missing provenance/ACL.
5. Migrate with stable IDs and idempotent upserts to MongoDB collections in a dedicated database.
6. Verify read parity and scope isolation with all connected agent adapters before cutover.
7. Change `backend=hybrid` (or `mongodb`) once, restart clients safely and test cross-agent checkpoint retrieval.
8. Keep immutable backup and rollback path; no background dual-write synchronization.

## 4. Failure matrix

| Failure | Expected action |
|---|---|
| Mongo unreachable, Redis working | Disable durable writes and task claims, show error; no Redis-only writes |
| Redis unreachable, Mongo working | Read/write Mongo normally, local cache or miss, recover status via Mongo polling |
| Both unreachable | Fail closed; no silent creation of SQLite copy |
| Local SSD unplugged | Reject affected paths and recover after remount, no shadow files |
| Redis restarted | Rebuild ephemeral caches; reconcile task truth in Mongo |
| Worker crash | Resume by lease expiry with duplicate-safe idempotency guard |

## 5. Relocating managed data

`omnimem relocate` only moves OmniMemo-owned local cache/config/artifacts. For MongoDB server's own `dbPath` or Redis `dir`, obtain process-owner permission, use vendor-supported backup or clean stop then copy, validate file system, restart, verify, and keep rollback. No blind live file-copy of running MongoDB or Redis persistence directories.

## 6. Sanity checks

- Project isolation works even if two projects have the same query and branch names.
- No disk cache > configured cap (default 32 MiB global, reach subcap 8 MiB); external service data not counted in that cap.
- Redis namespace memory usage is observed and bounded via TTL/item size; no automatic mutation of existing server-wide maxmemory.
- No test result is claimed without an actual running MongoDB/Redis fixture.
- No repository push without a fresh explicit user approval and authenticated `YanIanZ` Git identity.
