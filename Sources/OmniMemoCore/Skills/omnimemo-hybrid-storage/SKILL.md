---
name: omnimemo-hybrid-storage
description: Use only for MongoDB+Redis or SQLite backend configuration, migration, diagnostics, performance or recovery in OmniMemo.
---

# OmniMemo Hybrid Storage v1.8 (Proposed Workflow)

1. Before touching databases, read `AGENTS.md` and `docs/OmniMemo_Hybrid_Storage_Technical_Spec_v1.8.md`.
2. Choose explicit `hybrid`, `mongodb`, or `sqlite` profile; never auto-fallback writes to SQLite.
3. Use MongoDB for durable memory, task ownership, approvals and checkpoint truth. Redis cache and signaling are disposable.
4. Check available capabilities (Mongo standalone vs replica set, Redis auth and namespace) rather than assuming transactions or streams.
5. No secrets in repository, prompt, logs, or memory. Read DSNs from approved env / secret manager.
6. Never change global Redis configuration, wipe shared Redis, overwrite user collections, stop DB services or migrate server data without explicit permission.
7. Observe scoped caching, TTL, revision, provenance, idempotent task lease rules. Verify outage behavior with test fixtures if available.
8. Preserve anti-overengineering, OmniBias evidence rules, REA and Reach permissions, and YanIanZ-only approved GitHub push.
9. All `omnimem storage ...` commands referenced in specs are proposals, not working commands until implemented.
