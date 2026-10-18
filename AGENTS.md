# OmniMemo — Universal Agent Rules (Canonical)

Applicable to Codex, Claude Code, Gemini CLI, OpenCode, and any future coding agent operating on this repository. The human owner is the final authority. Do not override system or platform rules.

## 1. Engineering / Anti-Overengineering (MUST)

1. Implement exactly the requested scope; do not add speculative features, dashboards, distributed services, frameworks, or unrelated refactors.
2. Use the smallest working implementation; prefer Swift + MongoDB and the existing project modules.
3. Propose any new heavyweight dependency, background daemon, remote service, abstraction layer, or database before implementing it. Explain why a simpler option cannot work.
4. First build/test the save -> recall -> cross-agent handoff vertical slice before optimizations.
5. Avoid "future-proofing" interfaces/traits without a current second use case. Never add a plugin system only for one plugin.
6. Profile before optimizing. Treat cache=32MiB and RAM targets as measured targets, not excuses for unsafe behavior.
7. Keep scoped changes small and code explicit. Handle actual errors; avoid massive error-handling frameworks.
8. Tests must cover behavior and relevant failure cases. Do not skip security/recovery tests to appear lightweight.
9. Stop after acceptance criteria pass, provide concise diff/test summary, and mention remaining limitations.
10. Do not duplicate source-of-truth config, memory, identity policies, or instructions per agent.

## 2. GitHub Identity Lock (MUST)

1. Authorized GitHub owner: **YanIanZ**. All newly agent-authored commits use author AND committer name `YanIanZ` and a GitHub-verified/noreply email that the owner explicitly configures. Never invent an email.
2. No AI/bot identity or automatic AI `Co-authored-by` / `Signed-off-by` / generated-by attribution. Do not forge legitimate third-party attribution.
3. Allowed push destination is only a specifically approved repo under `github.com/YanIanZ/`. Check effective push URL; fetch URL is not enough.
4. Verify Git author/committer via `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT`; verify authenticated GitHub account separately (SSH key or applicable HTTPS credential). `gh auth status` alone is not proof of Git push identity.
5. **Never `git push` without explicit human approval for that push.** Permission to edit files or commit is not permission to push.
6. No force-push, tag/branch delete, mirror push, history rewrite, remote mutation, Git credential changes, or bypassing hooks. Ask user before any such operation.
7. Never write access tokens, SSH keys, passwords, or cookies to repository, prompts, logs, OmniMemo, or memory checkpoints.
8. If author, email, authentication, remote, or user approval cannot be verified, stop the push and report exactly what failed.
9. Existing legitimate commits by other contributors must not be rewritten to fake ownership. Ask for policy exception when collaboration requires it.
10. Do not change Git `core.hooksPath`, signing configuration, identity, account, or remote automatically. The user must opt in to hook installation.

## 3. Work Routine

- Start: state goal, scoped files, simplest plan, success criteria.
- Implement: make minimal changes and test impacted behavior.
- Memory: store checkpoints, decisions, bugs and evidence, never secrets; do not indiscriminately capture full chat.
- Before commit: show identity, review changes and test outcome; do not fabricate authorship.
- Before push: show destination, acting GitHub account, commit range, and request explicit approval.
- Finish: changed files, tests, limitations, no unrelated work.

See `docs/OmniMemo_PRD_v1.2_Guardrails.md`, sections 24–26 for the binding rationale and acceptance criteria.

User override (2026-10-18): Swift + MongoDB replace Rust + SQLite/FTS5 in the archived PRD. A local MongoDB service is required; the earlier no-database-service constraint is superseded.
