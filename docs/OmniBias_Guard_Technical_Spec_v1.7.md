# OmniBias Guard — Technical Design Specification v1.7

**Part of OmniMemo.** Proposed implementation, not a deployed service. The canonical all-agent rules are in `AGENTS.md`. Source PRD: `OmniMemo_PRD_v1.7_OmniBias_Guard.md`, sections 83–99.

## One-sentence contract

Maintain independently checkable evidence for meaningful claims and let cross-provider workers disagree safely, without automatically spawning more models or promoting consensus into fact.

## Vertical slice

1. Codex creates a checkpoint containing a claim marked `hypothesis` and a test reference.
2. Claude recalls it in a different runtime: sees origin, scope, limitations, and unchanged status.
3. Claude evaluates the file/tests independently without prior agent's preferred answer if review mode is requested.
4. OmniMemo stores `supported`, `disputed`, or `verified_test` status based on observed evidence; never on provider prestige.
5. Gemini reads compact merged findings, optionally runs tests, and records an accurate outcome.

## DB strategy

Use **existing SQLite** tables and graph edges. Add minimal nullable metadata such as `evidence_lineage`, `risk_flags`, `review_status` through backwards-compatible schema migration only if existing metadata cannot represent these. Use primary-source hashes/URLs/digests. Compact structured items are preferred to raw transcripts. No new vector DB, model judge, or mandatory external service.

## Algorithm (deterministic P0)

- Validate schema and project/branch ACL.
- Classify evidence type `user_requirement`, `test_result`, `source_reference`, `inference`, `opinion` and `unknown`.
- Reject untrusted text as instructions; apply existing Memory Guardian provenance/security gates.
- Validate evidence freshness and original source lineage, and compare claims against observed build/test status.
- Produce compact risk flags and explicit unknowns. Never output an uncalibrated bias percentage.
- Optional: in `critical` mode request authorization and hand a blind capsule to one distinct reviewer if it would materially reduce risk.

## Risk response

- `unsupported`: don't silently store as fact; label hypothesis.
- `stale`: include source version mismatch, suggest recheck.
- `disputed`: preserve both findings and evidence; choose test plan or ask user.
- `provider_unavailable`: complete deterministic validation and do not claim an independent audit occurred.
- `budget_exhausted`: summarize observed facts and limitations without fabricated conclusion.

## Fairness policy

For apps that affect people, choose user-relevant fairness metrics before data collection, test controlled counterfactual inputs where appropriate and protect sensitive data. Treat measures as contextual; never claim all biases removed because a benchmark passed. Normal coding fixes do not automatically get demographic or ethics checks.

## Integration rule

Provider identity is used for operational routing and debugging only. No source gets more credibility for originating from Codex/Claude/Gemini/OpenCode. Reach source lineage de-duplicates reposts; REA findings remain tool interpretations until independently checked; GitHub push is always owner-authorized YanIanZ only.

## Minimal API/config

Use optional `bias_mode=fast|balanced|critical` on existing `memory_context`. Add risk flags to existing response schema. Avoid separate MCP tool until a real consumer proves it necessary. Proposed CLI audit/report commands are optional.

## Acceptance and evidence

See BIAS-T01..BIAS-T20 in cumulative PRD. Key benchmark: correct completion rate, unsupported claim and stale-memory rate versus cost/latency/token use. Must preserve privacy, project isolation, readable source evidence and support offline mode.
