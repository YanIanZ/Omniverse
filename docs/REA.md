# REA integration (OmniMemo 0.2.0)

OmniMemo includes the complete public investigation skill from [YanIanZ/rea](https://github.com/YanIanZ/rea), pinned at `94153f1c757e07a6d092e00903aa8b125d4a0afa` (package version 6.4.0). The generated skill, six reference documents, upstream license and third-party notices are versioned in the Swift package. Upstream maintainer-only skills are not investigation features and are not installed into user projects.

The upstream runtime is built unchanged and launched through Swift with `execv`. This preserves its **184 MCP tools, six MCP prompts and 135 CLI commands**, including target-specific settings and caller-supplied engines. OmniMemo does not proxy, rename, filter or partially reimplement these operations. The four memory tools remain in their own MCP server.

## Prepare the matching runtime

```sh
cd /Volumes/Ext/MinionsProject/OmniMemo
python3 scripts/prepare-rea.py
./scripts/package.sh
BIN=/Volumes/Ext/DevCache/OmniMemo/dist/0.2.0/omnimem
"$BIN" rea status
```

Preparation fetches/builds only the pinned fork revision, uses its npm lockfile, disables Husky installation and Turbo telemetry, and stores checkouts, npm cache and build output under `/Volumes/Ext/DevCache/OmniMemo`. It does not run REA setup, modify agent configuration, install analysis engines, change Git identity or enable hooks. Node.js 22.19+, 24.11+ or 26+ and npm are required for REA; the current build was tested with Node 26.11.1.

Use `--base /external/path` for another cache location. If that manifest is not beside the executable, select it with `OMNIMEM_REA_RUNTIME=/external/path/integrations/rea-runtime.json` or `--runtime-manifest` on the REA command. No npm/package download occurs when `omnimem rea` is launched. A missing or changed entrypoint, lockfile, MCP bundle, catalog identity or mismatched bundled revision stops execution. This is a build/provenance check, not a claim that every byte in `node_modules` is independently authenticated on each call.

The release folder contains `rea-runtime.json` only when the prepared runtime exists at packaging time. It points to that external cached checkout, which must remain present. To move to another machine, run preparation there and use the resulting manifest; copying the Swift executable alone does not copy Node or all REA dependencies. `--vendor` refreshes versioned skill/provenance resources and is for an explicit reviewed source update, followed by build/tests/commit.

## CLI: all upstream commands

```sh
"$BIN" rea run -- --help
"$BIN" rea run -- --version
"$BIN" rea run -- analyze-javascript-application /absolute/path/to/extracted-app --json
"$BIN" rea run -- doctor --json
"$BIN" rea mcp  # full upstream MCP server on stdio
```

Arguments are passed without a shell. Stdout/stderr, input, signals and exit code belong to the upstream process. Working directory is the selected `--project`; REA still accepts explicit artifact paths under its own contracts. Temporary files are routed to the external runtime's private `rea-tmp` directory. Provider environment variables such as `GHIDRA_INSTALL_DIR`, `REA_ANALYSIS_PROVIDER`, `REA_IDA_MCP_CONFIG` and caller tool paths remain available to REA. Setup/update/uninstall commands forwarded explicitly are REA's own operations; they retain upstream review/approval behavior.

## Install into a project

```sh
PROJECT=/absolute/path/to/project
DATA=/Volumes/Ext/DevCache/OmniMemo/data
"$BIN" --data-dir "$DATA" --project "$PROJECT" install --with-rea
# Review additions before applying:
"$BIN" --data-dir "$DATA" --project "$PROJECT" install --with-rea --apply
```

The profile creates project-scoped Codex and Claude registrations for two servers:

- `omnimemo_<project>`: four memory tools, bound to the authorized project and configured datastore.
- `rea_<project>`: the complete upstream REA tools and prompts.

It also installs recall/handoff and the full `reverse-engineer-anything` skill tree, with Claude shims pointing to the canonical copies. `--rea-runtime-manifest PATH` selects a different reviewed runtime. Preview needs no running database or prepared REA; applying `--with-rea` validates runtime provenance and Node compatibility first. Repeated identical installation is a no-op. To change an existing memory-only profile, preview/uninstall its owned entries and then install the new profile; no existing entry is silently replaced. Normal `uninstall --apply` reads the recorded profile and removes both owned server entries and their skill files, preserving other settings and memory.

Default installation remains memory-only to avoid advertising REA's large catalog to unrelated coding tasks. The full REA profile can add substantial tool-schema context; there is no claim that enabling all 184 tools reduces token cost.

## Evidence → memory → handoff

REA findings are evidence, not automatically authoritative global memory. Keep only a useful decision/insight summary and a source reference:

```sh
"$BIN" --project "$PROJECT" rea run -- analyze-javascript-application "$PROJECT/extracted-app" --json > "$PROJECT/rea-evidence.json"
"$BIN" --data-dir "$DATA" --project "$PROJECT" memory save \
  --kind insight --title 'Observed application module boundary' \
  --content 'Describe the specific finding and its uncertainty here.' \
  --source rea-evidence.json
```

The equivalent agent workflow calls REA's connected tool, writes selected nonsecret evidence inside the authorized project, then calls `memory_save` and `memory_checkpoint`. A different memory client can retrieve the saved record with its source hash. Do not store raw captures, credentials or unreviewed runtime output by default. Sources must meet OmniMemo's existing path/size limits; use a compact reviewed evidence extract for large reports. Saving an analysis result does not prove a proposed reconstruction works; test that implementation separately.

## Capabilities and prerequisites

All upstream operation definitions are reachable. Their actual execution retains the upstream host/provider requirements:

| Capability | Prerequisite |
|---|---|
| JavaScript/Electron static analysis | Node/runtime; no native disassembler |
| Managed .NET, Go metadata, package/Apple artifact inspection | Supported artifact and upstream format coverage |
| Native decompilation | Existing Hopper, Ghidra or IDA with valid setup/license |
| Browser/Electron runtime inspection | Supported browser/app and requested connection |
| Android code/resources/device operations | Corresponding JADX/JDK, Apktool, adb or caller-started JEB |
| WASM | Caller-supplied WABT |
| Offline ELF/crash analysis, firmware, EVM and other specialized routes | Upstream platform/tool requirements; several are Linux-specific |

No paid engine, license or unsupported platform is bundled or claimed to be ready. Use `rea run -- doctor --json` and the upstream references for the specific tool needed. The integration preserves full functionality where those prerequisites are satisfied; the macOS test result does not establish all-provider conformance.

## Verified

Automated tests use the actual REA runtime through OmniMemo: complete tools/prompts discovery, real static JavaScript analysis over a fixture with imports, direct/wrapped CLI results and nonzero exit agreement, full skill installation/removal, and evidence-to-memory retrieval by a restarted client. No fake disassembler response or live commercial-engine result is used. Existing memory isolation/budget and adapter tests remain part of the suite.
