# Security policy

## Supported versions

OmniMemo is pre-1.0. Security fixes go into the latest release on `main` only.

## Reporting a vulnerability

Please do **not** open a public issue. Report it privately through GitHub: **Security → Report a vulnerability** on this repository ([private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)).

Include what you found, the steps to reproduce it, the affected version (`om --version`) and its impact. You will get an acknowledgement within a week; please give us a reasonable time to ship a fix before disclosing it.

## Scope

In scope:

- The `om` / `omnimem` binary, its MCP server and the Mission Control HTTP/WebSocket server (authentication, Host/Origin checks, approvals)
- Installers and host adapters (`install.sh`, `scripts/`, the Claude Code plugin, Codex/Gemini hooks, the OpenCode plugin)
- Secret filtering, project isolation and anything that could leak prompts, tool arguments or memory across projects

Out of scope: the security of your MongoDB or Redis deployment, other local processes that already have access to your data directory or database, and the bundled third-party REA engines (report those upstream).

See [Security and limits](README.md#security-and-limits) for the trust model.
