# OmniMemo Agent Rules Addendum v2.4

- Measure **active context occupancy** from verified host metadata. Lifetime tokens, API costs or rate limits are not context-window occupancy. Unknown stays unknown.
- If a supported provider is near its configured limit, create evidence-based checkpoint and a bounded Context Capsule. Never copy whole chat, private reasoning, credentials or secrets.
- Do not spawn a new agent process or control an IDE session without explicit opt-in and supported host API. For unmanaged sessions provide manual continuation.
- Wait until the current turn, tools and approvals are safely settled before rollover.
- Persist checkpoint and session intent in MongoDB/selected SQLite before requesting a child. Redis is ephemeral signaling only.
- Require a fresh session, not resume or history-fork. Transfer ownership only after child acknowledges the digest; on failure preserve parent and task ownership.
- Never globally block compaction without proven recovery behavior: a blocked Claude PreCompact after hitting context limit may cause a failed request; Gemini PreCompress is advisory.
- Distinguish task milestone progress from model context usage in Mission Control. Do not invent percentages.
- Minimize dependencies, work, overhead and token usage. Avoid extra model summaries and repeated indexing.
- Never alter Git remote/author/authentication automatically; only `YanIanZ`-authorized push credentials and explicit approval for **each push**.
- Do not claim that a feature is implemented merely because a specification or skill was installed. Always distinguish tested from proposed capabilities.
