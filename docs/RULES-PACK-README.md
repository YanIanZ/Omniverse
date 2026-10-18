# OmniMemo Agent Rules Pack v1.2

This is a **template**, not an installed GitHub protection rule and not an active hook until you enable it. The rules apply to developing OmniMemo itself and can be adapted for other repos.

## Contents
- `AGENTS.md`: canonical cross-agent policy, including minimal engineering and `YanIanZ` identity rules.
- `CLAUDE.md` / `GEMINI.md`: compatibility shims directing agents to the canonical policy.
- `.githooks/pre-commit`: local Git author/committer identity check.
- `.githooks/pre-push`: strict SSH-only push destination and identity check, branch-only, fast-forward, commit metadata.
- `docs/OmniMemo_PRD_v1.2_Guardrails.md`: detailed PRD.

## Install only with your consent

1. Copy files into the root of your OmniMemo repository **after reviewing them**.
2. In GitHub Settings > Emails, locate the exact verified or `noreply` commit email on your account.
3. Configure repository-local Git identity:

```bash
git config --local user.name YanIanZ
git config --local user.email 'YOUR_VERIFIED_GITHUB_EMAIL'
git config --local user.useConfigOnly true
git config --local omnimem.guard.email 'YOUR_VERIFIED_GITHUB_EMAIL'
```

4. Use an SSH remote belonging to `YanIanZ`. Check with `git remote get-url --push origin` and `ssh -T git@github.com`.
5. Check any existing `core.hooksPath` before enabling. If you already use custom hooks, **merge** these checks rather than replacing them.
6. Optionally enable local hooks:

```bash
chmod +x .githooks/pre-commit .githooks/pre-push
git config --local core.hooksPath .githooks
```

The sample `pre-push` script intentionally supports **SSH only** and allows only `origin` under `github.com/YanIanZ/`. It does **not** support HTTPS, SSH host aliases, `core.sshCommand` overrides, tag pushes, deletion, or non-fast-forward pushes. Adjust only after explicit policy approval and tests.

## Caveats
- Local Git hooks can be disabled or bypassed, including via `--no-verify`; GitHub authentication and repository permissions are a separate server-side control.
- A hook cannot reliably determine whether a human actually authorized a push; agents must follow `AGENTS.md` and ask before pushing.
- `gh auth status` is not definitive proof of the key used by SSH `git push`.
- Hooks require Bash (compatible with stock macOS Bash 3.2) and Git. For cross-platform production, prefer implementing checks in Rust.
- A strict author/committer check can reject legitimate imported contributions. Never rewrite other contributors' authorship simply to pass the policy.
