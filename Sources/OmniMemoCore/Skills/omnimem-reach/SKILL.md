---
name: omnimem-reach
description: Fetch limited, cited external research evidence only when a coding task needs web facts; share concise sources with permitted Codex, Claude Code, Gemini CLI and OpenCode agents.
---

# OmniMemo Reach (on-demand)

Use only for external information not already supplied by the user or repository. First check existing memory and source freshness. Default READ ONLY; never post, edit, login, extract browser cookies or install tools automatically. Respect authenticated-source permission scopes.

1. Select native authorized connector if available; otherwise detect Agent Reach using `agent-reach doctor --json` without installing. Do not assume Agent Reach MCP supplies search/read (currently `get_status` only).
2. Check platform/channel capability, explicit consent, URL safety, privacy, and source Terms. If unavailable, report limitation and stop rather than bypass restrictions.
3. Fetch through verified allowlisted adapter, at most 4 sources and 600 tokens total by default. No arbitrary shell; no raw transcripts or HTML dumps.
4. Produce Evidence Capsule: claim, short excerpt, source locator, channel/backend if observed, retrieved time, freshness/uncertainties.
5. Store only useful project-scoped, secret-free, source-backed findings; use Task Capsule refs for other agents. No private content sharing across trust scopes.
6. GitHub write/push always blocked in Reach. Only explicit user-approved push to YanIanZ repo with verified identity through separately authorized workflow.

Canonical policy: `AGENTS.md` section 7. Technical guide: `docs/Omni_Reach_Bridge_Technical_Spec_v1.6.md`.
