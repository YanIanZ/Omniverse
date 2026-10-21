# Contributing to OmniMemo

Thanks for helping. Bug reports, fixes, docs and tests are all welcome. For a new feature, open an issue first so we can agree on scope before you write code.

## Ground rules

- **Small and explicit.** Fix or add exactly one thing per pull request. No speculative abstractions, new services or heavyweight dependencies without discussing them first ([AGENTS.md §1](AGENTS.md)).
- **Honest status.** Report what was observed: unknown stays unknown, tests you did not run are not claimed as passing.
- **No secrets** in code, tests, fixtures, logs or memory records.
- **Privacy by design.** OmniMemo never reads an agent's private conversation and reports tool activity by category only. Changes must keep it that way.

## Set up

Follow [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). In short:

```sh
git clone https://github.com/<you>/Omniverse.git OmniMemo && cd OmniMemo
./scripts/swift.sh build
./scripts/test-mongo.sh start
OMNIMEM_TEST_MONGO_URI=mongodb://127.0.0.1:27019/omnimemo_tests ./scripts/swift.sh test
(cd frontend && npm ci && npm run build)
```

## Before you open a pull request

- [ ] `./scripts/swift.sh test` passes (with the test MongoDB, so database tests are not skipped)
- [ ] `cd frontend && npm run build` passes, if you touched `frontend/`
- [ ] `claude plugin test plugins/omniverse-bridge-mod` passes, if you touched the plugin
- [ ] New behavior has a test, including the failure case that matters
- [ ] User-facing changes are reflected in the README or `docs/`, and noted under *Unreleased* in [CHANGELOG.md](CHANGELOG.md)

## Commits

[Conventional Commits](https://www.conventionalcommits.org/) prefixes (`feat:`, `fix:`, `docs:`, `test:`, `chore:`), with a subject that says what changes for the user, for example:

```
fix: stale and offline sessions leave the office at once
```

Commit under your own name. The identity rules in [AGENTS.md §2](AGENTS.md) and the hooks in `.githooks/` lock the maintainer's own coding agents to the maintainer's account; they are not meant for contributors, so do not enable `.githooks/` in your fork.

## Coding agents

If you work with Claude Code, Codex, Gemini CLI or OpenCode, they read [AGENTS.md](AGENTS.md) (through `CLAUDE.md`, `GEMINI.md`, `OPENCODE.md`). Review what your agent produces before submitting it; you are the author of the pull request.

## Reporting bugs

Use the bug report template. Include `om --version`, macOS and Swift versions, the storage profile, and the output of `om doctor` (it prints no secrets). Security issues go through [SECURITY.md](SECURITY.md), not public issues.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
