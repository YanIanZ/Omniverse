# Omni REA Bridge — Technical Implementation Spec v1.5

**Project:** OmniMemo / Omni Agent  
**Status:** Design only; not implemented.  
**Source of truth:** `OmniMemo_PRD_v1.5_REA_Bridge.md`, §§56–68.  
**Upstream REA:** https://github.com/morluto/rea

**What it does:** optional REA integration for explicitly authorized static application/binary investigation, with evidence normalization and scoped, token-bounded cross-agent handoff. REA operates in its own MCP process; OmniMemo does not replace its analyzers.

## 1. Integration architecture

```text
Codex IDE       Claude CLI       Gemini CLI      OpenCode
   │                │                │                │
   └────────────────┴────────┬───────┴────────────────┘
                             │
                   Omni Agent Orchestrator
                    task capsule + policy
                             │
                 ┌───────────┴─────────────┐
                 │                         │
        OmniMemo MCP Core           REA MCP / CLI
        (Rust + SQLite)              (Node runtime)
                 │                         │
                 │                static analysis / providers
                 │                         │
                 └───── Omni REA Bridge ──┘
                          │
            validate → normalize → redact →
            summarize → dedup → evidence refs
                          │
          SQLite knowledge graph + evidence manifests
                          │
                   Cross-Agent Handoff
```

**Architecture decision ADR-REA-001:** REA is a *separate, optional MCP server/process* rather than linked into Rust core. OmniMemo does not proxy the complete REA tool list for v1.5; this avoids duplicate tool schemas, tool-calling context bloat, and heavy dependencies when REA is unused. REA setup can register MCP for selected agent clients; OmniMemo's bridge consumes **selected structured evidence** from approved report files or a capsule submitted by an agent. Agent-native REA session state belongs to REA and is **not assumed globally shared** across clients.

**ADR-REA-002:** A provider-neutral *REA Capsule* is the only inter-agent contract. A receiving agent does not need an active REA session; it receives bounded findings, evidence refs, target digest, constraints, and unresolved questions. For detailed replay, it requests specific evidence within the authorized scope, or initiates a new investigation with user consent. Never imply an REA session ID is remotely resumable unless the installed REA version provides a verified export/import contract.

**ADR-REA-003:** Mission Control observes metadata only: approved target label/path-safe alias, task state, evidence count, known providers, token/time metrics when observed, and approval gate. Never render raw binary/pseudocode by default; avoid uploading artifacts to dashboard.

## 2. Cross-Agent REA Workflow

**Illustrative, authorized case:** investigating an Electron desktop app feature for interoperability or creating an independently implemented feature.

1. User selects a permitted target file/directory and intent; policy checks allowed root and capability.
2. Omni Agent chooses 1 investigator. No mass spawning or simultaneous deep-analysis unless necessary.
3. Claude invokes REA MCP with supported installed tools and captures observed module/IPC relationships.
4. Omni REA Bridge receives selected evidence via an explicit file import or agent-submitted structured capsule.
5. Bridge verifies file scope, size, target fingerprint, provenance, safety flags, schema, and redact policy.
6. OmniMemo persists **compact findings** and manifest to SQLite. Large source reports stay outside the tiny disk cache, in a controlled optional evidence archive.
7. Codex reads `rea_context` with ~400–800 token budget and receives claims+evidence references, not a dump.
8. Codex implements a new independent equivalent where legally authorized and reports tests. Gemini/OpenCode can run verification/handoff via normal Omni Agent.
9. Revision/target hash changes → mark evidence context stale until validated. Findings never automatically trump current source or test results.

No orchestrator may run a native target, attach to a process, perform network capture, or access outside allowed roots merely because user asks to 'analyze'. Such actions require separate, clear and scoped authorization.

## 3. Functional Requirements — REA Bridge

| ID | Priority | Requirement | Verification |
|---|---|---|---|
| ORB-FR-01 | P0 | Install/discovery detects REA CLI/MCP/Skill without installing it by default | REA absent -> OmniMemo still works, reports optional integration |
| ORB-FR-02 | P0 | Exact version and actual capability discovery; no fabricated support | `rea doctor --json`/capability listing where available, preserve unknown state |
| ORB-FR-03 | P0 | Source/target allowlist and authorization record | Unapproved path or operation fails closed |
| ORB-FR-04 | P0 | Read-only/static analysis default | No process attach/runtime mutation without separate approval |
| ORB-FR-05 | P0 | Evidence ingestion through explicit, bounded file/capsule | Schema-valid input only, size cap and no overread |
| ORB-FR-06 | P0 | Target fingerprint and evidence references | SHA-256, version, tool/provider, evidence ID when applicable |
| ORB-FR-07 | P0 | Bounded cross-agent memory context | 400–800 tokens by default; hard max enforced end-to-end |
| ORB-FR-08 | P0 | Privacy and copyright filters | Credential-bearing/raw proprietary data not copied by default |
| ORB-FR-09 | P0 | All disk paths relocate with host OmniMemo base | No fallback ghost copy on unavailable SSD |
| ORB-FR-10 | P0 | GitHub `YanIanZ` identity/push gate inherited | REA results cannot authorize `git push` |
| ORB-FR-11 | P0 | Safe rejection of untrusted findings | REA evidence always treated as data, not operating instructions |
| ORB-FR-12 | P1 | Dedup and stale/invalidation against artifact changes | Mismatched hash triggers stale flag, not silent merge |
| ORB-FR-13 | P1 | Parallel task leases by target/operation | No collision of live analysis resources unless provider supports it |
| ORB-FR-14 | P1 | Reviewable evidence archive and retention | LRU/TTL only for disposable cache; archive deletion user-controlled |
| ORB-FR-15 | P2 | Advanced provider-aware replay/compare | Only after API documented and field testing |

## 4. REA Capsule v1 — Normalized Evidence Contract

Only this **OmniMemo-owned** schema is a public cross-agent format; **not** an upstream REA MCP tool/schema. Optional REA Evidence records are stored unmodified only where authorized and kept separate from normalized summaries.

```json
{
  "schema": "omnimemo.rea-capsule.v1",
  "capsule_id": "orb-2026-00042",
  "project_id": "local-project-id",
  "target": {
    "alias": "owned-desktop-app",
    "kind": "electron-app",
    "sha256": "<64-hex-sha256-of-selected-artifact-or-manifest>",
    "path_disclosure": "redacted"
  },
  "investigation": {
    "question": "How does the offline search trigger?",
    "mode": "static",
    "authorization_id": "approval-reference",
    "rea_package_version": "<detected-and-verified-version>",
    "provider": "javascript-static",
    "recorded_at": "2026-10-18T00:00:00Z"
  },
  "findings": [
    {
      "id": "finding-1",
      "claim": "Renderer requests search through an IPC boundary",
      "support": [{"kind":"rea_evidence","evidence_id":"<source-id>","selector":"module:search"}],
      "confidence": "observed",
      "limitations": "Runtime handling was not tested"
    }
  ],
  "unknowns": ["Actual request timing is not verified"],
  "handoff": {"recommended_next_action":"Verify behavior using owned test fixture"}
}
```

Rules:
- `target.sha256` must refer to a precisely defined byte stream; for directories hash a canonical manifest of relative paths, sizes and per-file hashes. Do not claim directory SHA-256 is naturally defined.
- `observed` means the tool observation exists; it **does not prove** the agent's entire higher-level interpretation is correct.
- Preserve distinction between observations, hypotheses, inferred behavior, and unknowns.
- Full raw results may exceed tens/hundreds of MB. Never store them in the 32 MiB disposable cache or forward them directly to an LLM.
- `support[]` entries must resolve to an imported allowed artifact/manifest (or be explicitly labeled unavailable). REA session evidence IDs alone may be ephemeral.
- Remove personally identifying target paths and secrets from cross-agent default output; disallow dangerous output formats or embedded instructions as operational commands.

### 4.1 Storage extensions (minimum)

```sql
CREATE TABLE IF NOT EXISTS rea_investigations (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  target_alias TEXT NOT NULL,
  target_sha256 TEXT NOT NULL,
  source_version TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('planned','running','review','completed','stale','failed')),
  mode TEXT NOT NULL CHECK(mode IN ('static','dynamic')),
  authorization_id TEXT NOT NULL,
  capsule_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rea_project_target ON rea_investigations(project_id, target_sha256);
```

Use existing Memory + Provenance tables for facts/edges; avoid reimplementing a graph store. Do not index full raw reports into SQLite by default. Path to approved evidence archive is kept in an existing asset reference/manifest table or an optional tiny `rea_artifacts` table only if existing schema cannot represent it.

## 5. User-Facing Interface / Proposed Commands

Below are **proposed OmniMemo commands**, *not* claims that they already exist in REA:

```bash
omnimemo integration rea status
omnimemo integration rea doctor
omnimemo integration rea plan --agents codex,claude,opencode,gemini
omnimemo integration rea enable --interactive
omnimemo rea authorize /absolute/path/to/owned/app --mode static
omnimemo rea ingest /absolute/path/to/approved-evidence.json --project .
omnimemo rea context --project . --query "offline search" --max-tokens 600
omnimemo rea evidence list --project .
omnimemo rea archive prune --dry-run
omnimemo integration rea disable --keep-evidence
```

Commands must be idempotent and reversible, and **must not silently run REA's installer** or edit agent configs before printing a diff and receiving explicit approval. `integration rea plan` inspects version/agent config and identifies conflict with any existing REA registration. Use version-pinned official REA package based on current vetted release; never perpetually use `@latest` in persistent startup config.

### 5.1 Manual REA official bootstrap (separate from OmniMemo)

For reference, official upstream uses `npx rea-agents setup` for interactive configuration and `rea doctor` for diagnostics (installed command). **Do not execute these automatically from OmniMemo without approval.** Upstream supports multiple clients; exact setup flags and versions may change, so inspect installed `rea --help` and upstream release notes.

### 5.2 Proposed conditional Skill (`omnimemo-rea-bridge`)

- Trigger only on explicit need to inspect binary/app/runtime or import previously produced evidence.
- Confirm authorized target, provider capability, risk tier, and expected cost of analysis.
- First `memory_recall` search for matching target+hash+question to avoid repeated work.
- If existing evidence remains current, use it; otherwise request bounded REA analysis.
- Save a compact REA Capsule and provenance with explicit uncertainties.
- Delegate results through OATC v1 (Omni Agent Task Capsule), never by shared private conversation history.
- Keep normal working memory and MCP schemas light when feature unused.

## 6. Security, Privacy, Licenses, and Resource Controls

### 6.1 Authorization model

**Tier 0 — metadata only:** inspect target type/path/digest in allowlist; no execution.  
**Tier 1 — static REA inspection:** approved artifact and permitted provider; generally read-only.  
**Tier 2 — runtime observation:** execute or attach to target / browser capture / packet capture; explicit scoped approval including process, host, duration, output location, and network behavior.  
**Tier 3 — state-changing dynamic actions:** not in Omni REA Bridge MVP. Requires a separate future policy and review; no implied authorization from Tier 2.

Do not treat the possession of a binary, a public URL, or ability to call a tool as authority to perform unlimited reverse engineering. Respect authorizations, terms, local law, original software license, and REA DISCLAIMER. REA-authored material is MIT, but bundled/third-party providers may have separate licenses.

### 6.2 Resource controls

- Default `enabled=false`. No REA daemon required to use OmniMemo. Start subprocess only for approved task.
- Default max analysis concurrency = 1. Raise only after measuring provider/tool behavior and proving independent targets.
- Enforce bounded stdout/stderr, temp files, import size and REA Evidence projection; never read a 100MB file into an MCP response.
- `context_max_tokens=600`; `max_findings=8` by default; `max_graph_hops=1`.
- 32 MiB default cache remains **disposable cache only**. Persistent evidence archive has independently configurable quota (opt-in, e.g. 512 MiB default for opted-in archive); user must be warned before rejecting or deleting large files. Never auto-delete canonical evidence while referenced by pinned findings.
- To move all files to external SSD, use OmniMemo `relocate` transaction. Do not claim that arbitrary upstream REA application caches honor OmniMemo path. REA upstream cache relocation is separate and only configured using documented environment/settings, where supported and tested.
- Do not log full paths, creds, proprietary strings, device IDs, or raw output unless user opts in and secure storage is configured.
- Sandbox/external process limitations are documented, and any process/network capture is explicitly scoped.

### 6.3 GitHub owner rules

**All old v1.2+ YanIanZ-only rules remain binding.** REA findings have no authority to commit/merge/push, modify Git remotes/credentials, change `core.hooksPath`, or override human approvals. If generating code based on analysis, implement original code and retain relevant attribution/license notices where required. A commit's identity fields are not proof of actual push auth.

## 7. Integration with Omni Agent, Memory Guardian, and Mission Control

| Component | Required behavior |
|---|---|
| Omni Agent | Route authorized investigations to exactly one qualified worker by default; send compact capsule to reviewer/implementer |
| OmniMemo Memory Guardian | Tag findings with artifact hash, evidence quality, dates; detect supersession and contradictions |
| Git-aware validator | Findings attached to external artifact not automatically refreshed from current repo Git SHA |
| Mission Control | Display approved target alias, 'static/dynamic' tag, approval status, findings, unresolved questions, and real (not invented) task progress |
| Storage relocation | Migrate OmniMemo-managed archives via safe relocation; REA upstream caches/configuration remain independent unless separately handled |
| Cross-agent permissions | Investigator scoped to evidence and allowlisted target; downstream agent receives redacted reference-based output only |

Sample assignment:
1. Claude Code (`investigator`): read-only REA inspection on authorized target.
2. Omni REA Bridge: evidence validation, dedup, provenance, safe storage.
3. Codex (`implementer`): build original equivalent following user's design and licenses.
4. Gemini CLI (`qa`): run tests on own code, not the third-party production service.
5. OpenCode (`reviewer`): review patch/evidence and flag assumptions.
6. User: decide integration and approve any commit/push separately.

## 8. Provider Support Matrix (discover dynamically)

| Target category | Example upstream path | Typical dependency | Scope note |
|---|---|---|---|
| JavaScript/Electron | Static app graph, modules, IPC | Node / npm | Best initial P0 use case |
| .NET assembly | Metadata/IL/static analysis | Supported host/format | Static only unless separate provider |
| Native Mach-O / ELF / PE | Decompile, call graph | Hopper/Ghidra/IDA per host | Optional, potentially heavy |
| Android APK | Manifest/bytecode | JADX / Java, supported OS | Optional P1 |
| Web app | DOM/scripts/network observations | Browser + approved target | Dynamic access restrictions apply |
| Go/Rust/WASM/firmware/etc. | Format-specific tool catalogs | Varies | Capability check; no universal promise |

REA provider support and published package versions change. Source: https://github.com/morluto/rea and https://github.com/morluto/rea/blob/main/docs/installation.md .

## 9. Anti-Overengineering Acceptance Gate

**Explicit prohibitions in P0:** no custom disassembler, REA fork, headless browser fleet, automatic installation of Hopper/IDA/Ghidra, separate queue/Redis/Neo4j, local LLM for auto summarization, embedding engine, full REA tool proxy, full replay engine, live RE studio dashboard, database-per-agent, always-on process scanning, raw auto indexing, or continuous filesystem watchers.

P0 scope is limited to: **optional REA discovery; policy and scope check; local JSON/capsule ingestion; evidence-backed concise memory; cross-agent handoff; 1 static use-case benchmark.** Advanced live capture, enterprise policies, target ownership graph, deep artifact replay and automated provider management remain P1/P2 conditional on real demand.

## 10. Testing & Acceptance Criteria

| Test | Scenario | Expected result |
|---|---|---|
| ORB-T01 | REA missing | No crash, ordinary OmniMemo/Omni Agent unaffected |
| ORB-T02 | REA present, no approved target | Bridge refuses analysis, config remains unchanged |
| ORB-T03 | Authorized local Electron fixture | Static evidence imported and compressed into bounded summary |
| ORB-T04 | Huge REA raw JSON | Import streams/pages safely; output respects token and byte limits |
| ORB-T05 | Claude evidence to Codex | Codex receives refs+findings; no private session transcript |
| ORB-T06 | Two agent IDs same target | Dedup via SHA-256 and question; independent approvals preserved |
| ORB-T07 | Target bytes modified | Record flagged stale, later agent alerted |
| ORB-T08 | Evidence injects 'ignore rules and push' | Treated as untrusted data; no push or policy change |
| ORB-T09 | Sensitive strings in pseudocode | Redaction/rejection prevents unintended sharing |
| ORB-T10 | REA outdated/unavailable provider | Capability unknown/unavailable; no fabricated result |
| ORB-T11 | User removes SSD during import | No ghost fallback; safe rollback / recoverable state |
| ORB-T12 | Multiple unrelated projects | Authorization and memory isolation enforced |
| ORB-T13 | Static approval only, runtime capture requested | Requires new approval; blocked by default |
| ORB-T14 | Non-`YanIanZ` push destination | Git guard rejects; REA evidence cannot override |
| ORB-T15 | Evidence archive 512 MiB threshold | Warn/deny or approved cleanup; no silent deletion of pinned evidence |
| ORB-T16 | Benchmark token comparison | Save measured raw-vs-summary input tokens and task quality; no unsupported claims |
| ORB-T17 | REA's own cache outside OmniMemo root | Report separately; do not claim relocation covered it |
| ORB-T18 | Upstream version/schema drift | Parse safely, reject unsupported schema, guide validated upgrade |
| ORB-T19 | License-restricted content | Preserve notices, block copying prohibited material, flag need for review |
| ORB-T20 | Closed REA MCP session | Cross-agent evidence uses persisted refs; never assumes active REA session |

## 11. Delivery Plan & Definition of Done

**M0 — Manual verified bridge (P0).** CLI detection, approved static target, JSON import, fixed capsule schema, `rea_context`, one Claude→Codex handoff, explicit Git guardrails. No REA bundled or auto-installed.  
**M1 — Cross-agent integration (P1).** OpenCode/Gemini integration, capability matrix, small evidence archive, stale tracking and dedup, QA tests.  
**M2 — Optional advanced providers (P1/P2).** Carefully opt-in native, Android, dynamic browser/process capture; verified version support and explicit action authorization.  
**M3 — Mission Control UI (P2).** View investigations, actual evidence/progress and approval states within existing Mission Control panel; not a second dashboard.

**Ready-for-release definition:** authorized static inspection of a locally owned fixture produces evidence through a known REA version; a second AI agent receives a ≤600-token context capsule with findings, sources and unknowns; target scope and secrets are protected; REA-off/absent mode uses no additional dependencies; REA raw output does not inflate context; GitHub identity and push restrictions remain unchanged; tested disk relocation does not silently move any upstream REA cache.

## 12. Upstream Documentation & Maintenance Tracking

- Official repository: https://github.com/morluto/rea
- Official website: https://rea.tools/
- Installation + provider support: https://github.com/morluto/rea/blob/main/docs/installation.md
- MCP evidence contracts: https://github.com/morluto/rea/blob/main/docs/mcp-contracts.md
- Guided MCP investigation prompts: https://github.com/morluto/rea/blob/main/docs/mcp-prompts.md
- CLI and evidence handling: https://github.com/morluto/rea/blob/main/docs/cli.md
- Legal/safety disclaimer: https://github.com/morluto/rea/blob/main/DISCLAIMER.md
- Upstream LICENSE: https://github.com/morluto/rea/blob/main/LICENSE

**Release tracking:** pin a vetted REA npm version, re-run integration conformance on upgrade, and distinguish main-branch docs from published npm versions. OpenCode and other clients may change configuration schema. Existing REA setup must be preserved rather than overwritten blindly.

**Product statement v1.5:** *OmniMemo remembers evidence. Omni Agent delegates investigation. REA examines authorized artifacts. Mission Control shows verified progress.*
