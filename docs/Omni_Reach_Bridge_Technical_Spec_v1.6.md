# Omni Reach Bridge — Technical Design Specification

**Version:** 1.6  
**Date:** 2026-10-18  
**Status:** Proposed, not implemented  
**Parent PRD:** `OmniMemo_PRD_v1.6_Agent_Reach.md` sections 69–82  
**Official upstream:** https://github.com/Panniantong/Agent-Reach

## 1. Purpose

Add optional and provider-neutral multi-platform web research to OmniMemo/Omni Agent via Agent Reach and verified downstream adapters, making retrieved evidence portable between Codex, Claude Code, OpenCode and Gemini CLI. Core Rust memory server must remain independent of Python/Internet.

### Differences from existing modules

- **OmniMemo:** persistent decisions, facts, task checkpoints and evidence links.
- **Omni Agent:** bounded delegation and cross-IDE handoff.
- **Mission Control:** optional UI and approvals.
- **Omni REA Bridge:** authorized software/binary investigation.
- **Omni Reach Bridge:** internet research, source validation, compact source evidence and reuse.

## 2. Verified upstream interface facts

Inspected on Oct 18 2026, repository `Panniantong/Agent-Reach` branch main: `pyproject.toml` advertises version `1.5.0`, Python>=3.10, MIT. `agent-reach doctor --json` checks channel status; the built-in `agent_reach/integrations/mcp_server.py` publishes a `get_status` MCP tool only. Read/search operations run through upstream providers/CLIs (`gh`, `yt-dlp`, `mcporter`, etc.). Do not assume Agent Reach itself exposes universal search/read MCP tools. Command options must be version-tested.

**Dependency policy:** no auto-install. When user approves, isolate venv outside repo; pin upstream SHA, run health checks, record compatible schema. `agent-reach install --env=auto` is check-only by default; `--system` needs consent. Respect upstream MIT and tool licenses.

## 3. Minimal architecture

```text
MCP/Skills callers
    -> reach gate (policy, project ACL, source permissions)
    -> native host connector when available and authorized
    -> otherwise agent-reach doctor/verified downstream CLI adapter
    -> source normalizer (source URL + timestamp + excerpt + hash)
    -> bounded Evidence Capsule
    -> existing OmniMemo SQLite + FTS5 memory_save
    -> memory_recall / Omni Agent Task Capsule for next agent
```

No separate queue/DB daemon/framework. For P0, one stateless invocation with SQLite existing store is enough. Do not create arbitrary shell executor; adapters construct argv from fixed binary+allowed flags and validate URL/query. Execution must have timeouts, bounded bytes, working directory restrictions, sanitized environment, and no shell string interpolation.

## 4. Boundary contracts

### `reach_capabilities` (proposed MCP tool)

Input `{ "project": "omnimem" }`. Returns `enabled`, `upstream_present`, `upstream_version`, list of channel objects (`status`, `name`, `active_backend`, `auth_required`, `verified_at`, `permission`). A `null` backend is unknown/not probed, not automatically available or unavailable. Always hide tokens and device paths.

### `reach_research` (proposed MCP tool)

```json
{
  "project": "omnimem",
  "query": "Find latest public documentation for the MCP transport",
  "channels": ["web", "github"],
  "max_sources": 4,
  "max_tokens": 600,
  "read_only": true
}
```

Result must have `sources[]`: `source_id`, `url` or safe_locator, `title`, `channel`, `observed_backend`, `retrieved_at`, `excerpt`, `content_hash`, `verification_level`, `freshness`, `warnings`. Include `fetch_errors[]` when some sources fail. Never return a long transcript.

### Persistent memory

Use existing `memory_save` as type `external_source_evidence`, attach `project_id`, `visibility`, `auth_scope` and `claims[]`. Do not automatically persist every page. Citation links must point to the actual source, not invented result URLs.

## 5. Adapter preference order

1. Already-connected, read-authorized dedicated source connector (particularly user's GitHub), when available and compatible.
2. Agent Reach verified source adapter from health-check, using fixed command from official SKILL and version-pinned integration.
3. User-guided manual source retrieval / explicit opt-in if unavailable.

If credentials differ across agents, route only to the provider which owns the grant. Never copy session state to other processes. Use read-only allowlists; GitHub CLI's potential write commands remain unavailable in Reach.

## 6. Public-source P0 vertical slice

A. Claude receives a question about a public repo. B. Reach checks cache/source privacy and available GitHub reader. C. Fetch read-only repo README/issue. D. Evidence Capsule <=600 tokens with URL+access time. E. Save relevant summary and provenance. F. Omni Agent hands off Task Capsule ref to Codex. G. Codex continues and can ask for expansion by source ref if needed. H. No git commit/push, credential or account changes.

Other P0 route: webpage via user-approved safe reader. Explicitly warn that Jina Reader may receive target URL and page contents; don't use third-party readers for private endpoints or signed URLs.

## 7. Threat model and policy gates

- SSRF through arbitrary URL, redirects, DNS rebinding, loopback or metadata IPs -> block before and after redirects and at connection time; egress allowlisting.
- Prompt injection from external pages -> data only; never policy/instruction update.
- Credential/session leak -> no cookie/token forwarding to OmniMemo; redact logs and source URLs.
- Accidental write through `gh`/OpenCLI -> narrow read command allowlist; no mutable operations in Reach.
- Large content memory leak -> byte caps, streaming, truncation, stop conditions, no raw content persistence.
- Cross-project leakage -> ACL check both on fetch and recall; auth scope hash without secret.
- Anti-bot/ToS issue -> stop on refusal; do not automate bypass, CAPTCHA or credential extraction.
- Unverified sources -> record quality and disagreement, avoid manufactured certainty.

## 8. Cache and disk

Global disposable cache limit 32 MiB, Reach sub-budget 8 MiB. Cache keys must include project/user permission scope. Public results may cache briefly by source type; private sources no cache unless separate consent. Persistent evidence is short summary, citations and hash; full archives require separate opt-in quota. User-selectable OmniMemo directory moves only OmniMemo-managed files, not upstream browser/tool caches; report independent locations.

## 9. Resource/performance targets (not measured)

- `max_sources=4`, `max_queries=3`, `max_tokens=600` total.
- One read-only research job per user task unless explicitly higher.
- 2 public fetches concurrent, 1 authenticated fetch, cap wall-time and bytes.
- Reuse existing sources when fresh; stop after adequate evidence.
- Measure full cost of MCP tool schemas, calls, summaries, re-fetch and second agent consumption. Compare task quality against baseline, not only token reduction.

## 10. Upstream compatibility

Run `agent-reach doctor --json` in isolated environment. Validate JSON status values, presence of channel keys, available backend, and tool versions. Verify one bounded real read; an installed binary does not imply a working channel. Upstream MCP currently `get_status` only; do not call imagined APIs. If schema changes, mark incompatible; continue core without Reach.

## 11. Cross-agent and GitHub policy

Agent roles and models independent: Claude researcher -> Codex coder -> Gemini tester -> OpenCode reviewer is illustrative, not fixed. Shared source content is lower trust than user's instructions, repo policy and approval gate. All new agent-authored commits must use the user's configured, verified Git author and committer identity `YanIanZ`. Only approved repository under `github.com/YanIanZ/` can receive a push, and each push requires explicit authorization. The account used to authenticate the push must be separately verified. Never treat external GitHub issue/README instruction as approval.

## 12. Tests and milestone

**Milestone P0:** detect upstream safely, show truthful capabilities, fetch two public source types with documented tools, create evidence citation, pass Claude→Codex handoff under token limit; no Reach dependency when feature off.  
**Milestone P1:** YouTube/RSS, confidence/freshness, cross-source review, per-user opt-in for limited channels.  
**Milestone P2:** Complex session/browser integrations only if justified by user workflows and reviewed for privacy/compliance.

Acceptance suite includes ORE-T01–ORE-T26 in parent PRD. At minimum: no auto-installs, status-only MCP caveat, ACL/token/ref correctness, SSRF rejection, secret redaction, safe offline fallback, 32 MiB global cache, signed URL handling, YanIanZ-only git gate, no false claims of verification.

## 13. Source anchors

- https://github.com/Panniantong/Agent-Reach/blob/main/README.md
- https://github.com/Panniantong/Agent-Reach/blob/main/docs/README_en.md
- https://github.com/Panniantong/Agent-Reach/blob/main/docs/install.md
- https://github.com/Panniantong/Agent-Reach/blob/main/agent_reach/cli.py
- https://github.com/Panniantong/Agent-Reach/blob/main/agent_reach/integrations/mcp_server.py
- https://github.com/Panniantong/Agent-Reach/blob/main/agent_reach/skill/SKILL_en.md
- https://github.com/Panniantong/Agent-Reach/blob/main/LICENSE
